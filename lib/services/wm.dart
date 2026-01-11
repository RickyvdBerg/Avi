import 'dart:async';

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
}

abstract class CompositorWindowService extends ListenableService {
  static CompositorWindowService get current {
    return ServiceManager.getService<CompositorWindowService>()!;
  }

  /// Windows in stable taskbar order (order they were opened)
  List<CompositorWindowEntry> get windows;
  
  /// Windows in z-order (back to front, last = topmost)
  List<CompositorWindowEntry> get windowsByZOrder;
  
  bool isMinimized(int handle);
  bool isMaximized(int handle);
  int? get activeHandle;

  void setActive(int handle);
  void toggleMinimize(int handle);
  Future<void> toggleMaximize(Surface surface, bool maximized);
  Future<void> close(Surface surface);
}

class _CompositorWindowServiceImpl extends CompositorWindowService {
  final Compositor _compositor = Compositor.compositor;
  final Map<int, Surface> _surfaces = {};
  final Map<int, String> _titles = {};
  final Set<int> _minimized = {};
  final Set<int> _maximized = {};
  
  /// Stable order for taskbar display (order windows were created)
  final List<int> _taskbarOrder = [];
  
  /// Z-order for stacking (last = topmost/focused)
  final List<int> _zOrder = [];
  
  StreamSubscription<Surface>? _surfaceMappedSub;
  StreamSubscription<Surface>? _surfaceUnmappedSub;
  StreamSubscription<Surface>? _surfaceUpdatedSub;

  int? _activeHandle;

  @override
  int? get activeHandle => _activeHandle;

  @override
  List<CompositorWindowEntry> get windows {
    // Return windows in stable taskbar order
    return _taskbarOrder
        .where(_surfaces.containsKey)
        .map((handle) => _createEntry(handle))
        .toList(growable: false);
  }

  @override
  List<CompositorWindowEntry> get windowsByZOrder {
    // Return windows in z-order (for rendering)
    return _zOrder
        .where(_surfaces.containsKey)
        .map((handle) => _createEntry(handle))
        .toList(growable: false);
  }

  CompositorWindowEntry _createEntry(int handle) {
    return CompositorWindowEntry(
      surface: _surfaces[handle]!,
      title: _titles[handle] ?? 'Application $handle',
      appId: _surfaces[handle]!.appId,
      minimized: _minimized.contains(handle),
      maximized: _maximized.contains(handle),
      active: handle == _activeHandle,
      zIndex: _zOrder.indexOf(handle),
    );
  }

  @override
  bool isMinimized(int handle) => _minimized.contains(handle);

  @override
  bool isMaximized(int handle) => _maximized.contains(handle);

  @override
  void start() {
    _initCompositor();
  }

  @override
  FutureOr<void> stop() {
    _surfaceMappedSub?.cancel();
    _surfaceUnmappedSub?.cancel();
    _surfaceUpdatedSub?.cancel();
    _surfaces.clear();
    _titles.clear();
    _minimized.clear();
    _maximized.clear();
    _taskbarOrder.clear();
    _zOrder.clear();
  }

  Future<void> _initCompositor() async {
    final bool isCompositor = await _compositor.isCompositor();
    if (!isCompositor) return;

    _surfaceMappedSub = _compositor.surfaceMapped.stream.listen((surface) {
      _surfaces[surface.handle] = surface;
      _titles[surface.handle] = _resolveTitle(surface);
      _taskbarOrder.add(surface.handle);
      _zOrder.add(surface.handle);
      _activeHandle = surface.handle;
      notifyListeners();
    });

    _surfaceUnmappedSub = _compositor.surfaceUnmapped.stream.listen((surface) {
      _surfaces.remove(surface.handle);
      _titles.remove(surface.handle);
      _minimized.remove(surface.handle);
      _maximized.remove(surface.handle);
      _taskbarOrder.remove(surface.handle);
      _zOrder.remove(surface.handle);
      if (_activeHandle == surface.handle) {
        // Activate the next topmost non-minimized window
        _activeHandle = _zOrder.reversed
            .firstWhere((h) => !_minimized.contains(h), orElse: () => -1);
        if (_activeHandle == -1) _activeHandle = null;
      }
      notifyListeners();
    });

    _surfaceUpdatedSub = _compositor.surfaceUpdated.stream.listen((surface) {
      _titles[surface.handle] = _resolveTitle(surface);
      notifyListeners();
    });
  }

  String _resolveTitle(Surface surface) {
    final String? title = surface.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final String? appId = surface.appId?.trim();
    if (appId != null && appId.isNotEmpty) return appId;
    return 'Application ${surface.handle}';
  }

  @override
  void setActive(int handle) {
    if (!_surfaces.containsKey(handle)) return;
    _activeHandle = handle;
    // Only update z-order, NOT taskbar order
    _zOrder.remove(handle);
    _zOrder.add(handle);
    _minimized.remove(handle);
    notifyListeners();
  }

  @override
  void toggleMinimize(int handle) {
    if (!_surfaces.containsKey(handle)) return;
    if (_minimized.contains(handle)) {
      _minimized.remove(handle);
      _activeHandle = handle;
      // Bring to front in z-order
      _zOrder.remove(handle);
      _zOrder.add(handle);
    } else {
      _minimized.add(handle);
      if (_activeHandle == handle) {
        // Find next non-minimized window by z-order
        _activeHandle = _zOrder.reversed
            .firstWhere((h) => !_minimized.contains(h), orElse: () => -1);
        if (_activeHandle == -1) _activeHandle = null;
      }
    }
    notifyListeners();
  }

  @override
  Future<void> toggleMaximize(Surface surface, bool maximized) async {
    if (!_surfaces.containsKey(surface.handle)) return;
    if (maximized) {
      _maximized.add(surface.handle);
    } else {
      _maximized.remove(surface.handle);
    }
    await _compositor.platform.surfaceToplevelSetMaximized(surface, maximized);
    notifyListeners();
  }

  @override
  Future<void> close(Surface surface) async {
    if (!_surfaces.containsKey(surface.handle)) return;
    await _compositor.platform.surfaceToplevelClose(surface);
  }
}
