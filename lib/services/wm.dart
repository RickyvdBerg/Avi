import 'dart:async';

import 'package:avio_wm/avio_wm.dart' as avio;
import 'package:compositor_dart/compositor_dart.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:utopia_wm/wm.dart';

class WindowManagerServiceFactory extends ServiceFactory<WindowManagerService> {
  const WindowManagerServiceFactory();

  @override
  WindowManagerService build() {
    return _WindowManagerServiceImpl();
  }
}

class CompositorWindowServiceFactory
    extends ServiceFactory<CompositorWindowService> {
  const CompositorWindowServiceFactory();

  @override
  CompositorWindowService build() {
    return _CompositorWindowServiceImpl();
  }
}

abstract class WindowManagerService extends Service {
  WindowManagerService();

  static WindowManagerService get current {
    return ServiceManager.getService<WindowManagerService>()!;
  }

  WindowHierarchyController get controller;

  void push(LiveWindowEntry entry);
  void pop(String id);

  void minimizeEverything();
  void unminimizeEverything();
}

class _WindowManagerServiceImpl extends WindowManagerService {
  WindowHierarchyController? _controller;
  final Map<String, bool> _minimizedCache = {};

  @override
  WindowHierarchyController get controller {
    if (_controller == null) {
      throw Exception(
        "The window manager service is not currently running, can't obtain the controller",
      );
    }

    return _controller!;
  }

  @override
  void start() {
    _controller = WindowHierarchyController();
  }

  @override
  void stop() {
    _controller = null;
  }

  @override
  void push(LiveWindowEntry entry) {
    unminimizeEverything();
    controller.addWindowEntry(entry);
  }

  @override
  void pop(String id) {
    controller.removeWindowEntry(id);
  }

  @override
  void minimizeEverything() {
    _minimizedCache.addEntries(
      controller.entries.map(
        (e) => MapEntry(e.registry.info.id, e.layoutState.minimized),
      ),
    );

    for (final LiveWindowEntry e in controller.entries) {
      e.layoutState.minimized = true;
    }
  }

  @override
  void unminimizeEverything() {
    for (final LiveWindowEntry entry in controller.entries) {
      final bool? cachedStatus = _minimizedCache[entry.registry.info.id];

      entry.layoutState.minimized = cachedStatus ?? false;
    }

    _minimizedCache.clear();
  }
}

/// Simple container for taskbar/UI compatibility.
/// Maps WindowEntry to the old CompositorWindowEntry interface.
class CompositorWindowEntry {
  final Surface surface;
  final String title;
  final String? appId;
  final bool minimized;
  final bool maximized;
  final bool active;
  final int zIndex;

  const CompositorWindowEntry({
    required this.surface,
    required this.title,
    required this.appId,
    required this.minimized,
    required this.maximized,
    required this.active,
    required this.zIndex,
  });

  /// Create from an avio WindowEntry.
  factory CompositorWindowEntry.fromWindowEntry(
    avio.WindowEntry entry,
    int zIndex,
    bool active,
  ) {
    return CompositorWindowEntry(
      surface: entry.surface,
      title: entry.title,
      appId: entry.appId,
      minimized: entry.minimized,
      maximized: entry.isMaximized,
      active: active,
      zIndex: zIndex,
    );
  }
}

/// Abstract interface for compositor window management.
/// Used by taskbar and other UI components.
abstract class CompositorWindowService extends ListenableService {
  static CompositorWindowService get current {
    return ServiceManager.getService<CompositorWindowService>()!;
  }

  /// The underlying window manager.
  avio.WindowManager get windowManager;

  /// Windows in stable taskbar order (order they were opened)
  List<CompositorWindowEntry> get windows;

  /// Windows in z-order (back to front, last = topmost)
  List<CompositorWindowEntry> get windowsByZOrder;

  /// Active popups (menus, dropdowns, tooltips)
  List<Popup> get popups;

  /// Get popups for a specific parent surface handle
  List<Popup> getPopupsForSurface(int parentHandle);

  bool isMinimized(int handle);
  bool isMaximized(int handle);
  int? get activeHandle;

  void setActive(int handle);
  void toggleMinimize(int handle);
  Future<void> toggleMaximize(Surface surface, bool maximized);
  Future<void> close(Surface surface);

  // NOTE: beginMove, beginResize, and setWindowPosition have been removed.
  // Move/resize is fully Dart-controlled via WindowManager in avio_wm.
  // UI components call WindowManager methods directly via WindowLayer/WindowFrame.
}

/// Implementation that wraps WindowManager from avio_wm.
class _CompositorWindowServiceImpl extends CompositorWindowService {
  avio.WindowManager? _windowManager;

  @override
  avio.WindowManager get windowManager {
    if (_windowManager == null) {
      throw StateError('CompositorWindowService not started');
    }
    return _windowManager!;
  }

  @override
  List<CompositorWindowEntry> get windows {
    if (_windowManager == null) return [];
    final wm = _windowManager!;
    return wm.windows
        .map((entry) => CompositorWindowEntry.fromWindowEntry(
              entry,
              wm.zIndexOf(entry.handle),
              entry.handle == wm.activeHandle,
            ))
        .toList();
  }

  @override
  List<CompositorWindowEntry> get windowsByZOrder {
    if (_windowManager == null) return [];
    final wm = _windowManager!;
    return wm.windowsByZOrder
        .map((entry) => CompositorWindowEntry.fromWindowEntry(
              entry,
              wm.zIndexOf(entry.handle),
              entry.handle == wm.activeHandle,
            ))
        .toList();
  }

  @override
  List<Popup> get popups {
    return _windowManager?.popups ?? [];
  }

  @override
  List<Popup> getPopupsForSurface(int parentHandle) {
    return _windowManager?.getPopupsForSurface(parentHandle) ?? [];
  }

  @override
  bool isMinimized(int handle) => _windowManager?.isMinimized(handle) ?? false;

  @override
  bool isMaximized(int handle) => _windowManager?.isMaximized(handle) ?? false;

  @override
  int? get activeHandle => _windowManager?.activeHandle;

  @override
  void start() {
    _windowManager = avio.WindowManager(
      bridge: avio.PlatformCompositorBridge(),
      config: const avio.WmConfig(),
    );
    // Forward change notifications
    _windowManager!.addListener(notifyListeners);
  }

  @override
  Future<void> stop() async {
    _windowManager?.removeListener(notifyListeners);
    _windowManager?.dispose();
    _windowManager = null;
  }

  @override
  void setActive(int handle) {
    _windowManager?.activate(handle);
  }

  @override
  void toggleMinimize(int handle) {
    _windowManager?.toggleMinimize(handle);
  }

  @override
  Future<void> toggleMaximize(Surface surface, bool maximized) async {
    await _windowManager?.toggleMaximize(surface.handle);
  }

  @override
  Future<void> close(Surface surface) async {
    await _windowManager?.close(surface.handle);
  }
}
