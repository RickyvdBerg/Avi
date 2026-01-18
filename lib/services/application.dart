import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:compositor_dart/compositor_dart.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/window/window_surface.dart';
import 'package:pangolin/components/window/window_toolbar.dart';
import 'package:pangolin/services/langpacks.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/utils/wm/wm.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_desktop/xdg_desktop.dart';
import 'package:xdg_directories/xdg_directories.dart' as xdg;

class ApplicationServiceFactory extends ServiceFactory<ApplicationService> {
  const ApplicationServiceFactory();

  @override
  ApplicationService build() => _LinuxApplicationService();

  @override
  ApplicationService? fallback() => _BuiltInApplicationService();
}

abstract class ApplicationService extends ListenableService {
  ApplicationService();

  static ApplicationService get current {
    return ServiceManager.getService<ApplicationService>()!;
  }

  List<DesktopEntry> listApplications();

  FutureOr<void> startApp(String name);
  DesktopEntry? getApp(String name);
}

class _LinuxApplicationService extends ApplicationService {
  final Map<String, DesktopEntry> entries = {};
  final List<StreamSubscription<FileSystemEvent>> directoryWatchers = [];

  @override
  List<DesktopEntry> listApplications() => entries.values.toList();

  @override
  Future<void> startApp(String name) async {
    final DesktopEntry? app = getApp(name);

    if (app == null) {
      logger.warning(
        "The specified app $name can't be opened as it doesn't exist",
      );
      return;
    }

    final List<String> commandParts = app.exec!.split(" ");
    commandParts.removeWhere((e) => e.startsWith(RegExp("%[fuFU]")));

    final Map<String, String> environment = {
      ...Platform.environment,
    };

    // === Wayland environment hints for proper app behavior ===
    // These ensure apps use Wayland and respect server-side decorations
    // Set these ALWAYS, not just when compositor check succeeds

    // Firefox/Mozilla
    environment.putIfAbsent("MOZ_ENABLE_WAYLAND", () => "1");
    environment.putIfAbsent("MOZ_GTK_TITLEBAR_DECORATION", () => "system");
    environment.putIfAbsent("MOZ_DBUS_REMOTE", () => "0");

    // GTK
    environment.putIfAbsent("GDK_BACKEND", () => "wayland");
    environment.putIfAbsent("LIBDECOR_FORCE_SERVER_SIDE", () => "1");
    environment.putIfAbsent("GTK_CSD", () => "0");
    environment.putIfAbsent("XDG_CURRENT_DESKTOP", () => "Pangolin");

    // Qt
    environment.putIfAbsent("QT_QPA_PLATFORM", () => "wayland");
    environment.putIfAbsent("QT_WAYLAND_DISABLE_WINDOWDECORATION", () => "1");

    // Electron/Chromium
    environment.putIfAbsent("ELECTRON_OZONE_PLATFORM_HINT", () => "wayland");
    environment.putIfAbsent("NIXOS_OZONE_WL", () => "1");

    // SDL
    environment.putIfAbsent("SDL_VIDEODRIVER", () => "wayland");

    // GNOME/Clutter
    environment.putIfAbsent("CLUTTER_BACKEND", () => "wayland");

    // Java
    environment.putIfAbsent("_JAVA_AWT_WM_NONREPARENTING", () => "1");

    try {
      final bool isCompositor =
          await Compositor.compositor.isCompositor();
      if (isCompositor) {
        final sockets = await Compositor.compositor.getSocketPaths();
        environment["WAYLAND_DISPLAY"] = sockets.wayland;
        if (sockets.x.isNotEmpty) {
          environment["DISPLAY"] = sockets.x;
        }
      }
    } catch (error) {
      logger.warning("Failed to fetch compositor sockets", error);
    }

    Process.run(
      commandParts.first,
      commandParts.sublist(1),
      environment: environment,
    );
  }

  @override
  Future<void> start() async {
    await ServiceManager.waitForService<LangPacksService>();
    logger.info("Starting loading app service");

    _loadFolder(p.join(xdg.dataHome.path, "applications"));
    for (final Directory dir in xdg.dataDirs) {
      _loadFolder(p.join(dir.path, "applications"));
    }
    _loadFolder("/usr/share/applications");
  }

  @override
  DesktopEntry? getApp(String name) => entries.values.firstWhereOrNull(
        (e) => e.id == name,
      );

  Future<void> _loadFolder(String path) async {
    final Directory directory = Directory(path);
    final List<FileSystemEntity> entities;

    if (!directory.existsSync()) return;

    try {
      entities = await directory.list(recursive: true).toList();
    } catch (e) {
      logger.warning("Exception while listing applications for $path", e);
      return;
    }

    for (final FileSystemEntity entity in entities) {
      await _parseEntity(entity);
    }

    final Stream<FileSystemEvent> watcher = directory.watch();
    directoryWatchers.add(watcher.listen(_onDirectoryEvent));
  }

  Future<void> _parseEntity(FileSystemEntity entity) async {
    if (entity is! File) return;
    if (p.extension(entity.path) != ".desktop") return;

    final String content = await entity.readAsString();
    try {
      final DesktopEntry entry = DesktopEntry.fromIni(entity.path, content);
      if (entry.noDisplay == true || entry.hidden == true) return;

      if (entry.tryExec != null && !File(entry.tryExec!).existsSync()) return;

      final List<String> onlyShowIn = entry.onlyShowIn ?? [];
      final List<String> notShowIn = entry.notShowIn ?? [];

      if (onlyShowIn.isNotEmpty && !onlyShowIn.contains("Pangolin") ||
          notShowIn.contains("Pangolin")) {
        return;
      }

      if (entry.domainKey != null) {
        LangPacksService.current.warmup(entry.domain!);
      }

      entries[entity.path] = entry;
      notifyListeners();
    } catch (e) {
      logger.warning("Failed to parse desktop entry at '${entity.path}'");
      return;
    }
  }

  Future<void> _onDirectoryEvent(FileSystemEvent event) async {
    if (event.isDirectory) return;

    switch (event.type) {
      case FileSystemEvent.delete:
        entries.remove(event.path);
        notifyListeners();
      case FileSystemEvent.create:
      case FileSystemEvent.modify:
        await _parseEntity(File(event.path));
    }
  }

  @override
  Future<void> stop() async {
    for (final StreamSubscription watcher in directoryWatchers) {
      await watcher.cancel();
    }
  }
}

class _BuiltInApplicationService extends ApplicationService {
  final List<_BuiltinDesktopEntry> entries = [];
  final Map<DesktopEntry, Widget> builders = {};

  static const WindowEntry windowEntry = WindowEntry(
    features: [
      ResizeWindowFeature(),
      SurfaceWindowFeature(),
      FocusableWindowFeature(),
      ToolbarWindowFeature(),
    ],
    layoutInfo: FreeformLayoutInfo(
      position: Offset(32, 32),
      size: Size(1280, 720),
    ),
    properties: {
      ResizeWindowFeature.minSize: Size(480, 360),
      SurfaceWindowFeature.elevation: 4.0,
      SurfaceWindowFeature.shape: Constants.mediumShape,
      SurfaceWindowFeature.background: PangolinWindowSurface(),
      ToolbarWindowFeature.widget: PangolinWindowToolbar(
        barColor: Colors.transparent,
        textColor: Colors.black,
      ),
      ToolbarWindowFeature.size: 40.0,
    },
  );

  @override
  void start() {}

  @override
  _BuiltinDesktopEntry? getApp(String name) =>
      entries.firstWhereOrNull((e) => e.id == name);

  @override
  List<_BuiltinDesktopEntry> listApplications() => entries;

  @override
  void startApp(String name) {
    final _BuiltinDesktopEntry? app = getApp(name);

    if (app == null) {
      logger.warning(
        "The specified app $name can't be opened as it doesn't exist",
      );
      return;
    }

    WindowManagerService.current.push(
      windowEntry.newInstance(
        content: app.content,
        overrideProperties: {
          WindowExtras.stableId: app.id,
          WindowEntry.title: app.name.main,
          WindowEntry.icon: app.icon != null
              ? AssetImage(
                  app.icon!.main.toResource().resolve().toString(),
                )
              : null,
        },
      ),
    );
  }

  @override
  void stop() {
    entries.clear();
    builders.clear();
  }
}

class _BuiltinDesktopEntry extends DesktopEntry {
  final Widget content;

  const _BuiltinDesktopEntry({
    required super.id,
    required this.content,
    required super.type,
    required super.name,
  });
}
