/*
Copyright 2021 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:async';
import 'dart:math' as math;

import 'package:compositor_dart/compositor_dart.dart';
import 'package:compositor_dart/surface.dart';
import 'package:compositor_dart/widgets/compositor_surface_autosize.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/desktop/wallpaper.dart';
import 'package:pangolin/components/overlays/account_overlay.dart';
import 'package:pangolin/components/overlays/launcher/compact_launcher_overlay.dart';
import 'package:pangolin/components/overlays/notifications/overlay.dart';
import 'package:pangolin/components/overlays/overview_overlay.dart';
import 'package:pangolin/components/overlays/power_overlay.dart';
import 'package:pangolin/components/overlays/quick_settings/quick_settings_overlay.dart';
import 'package:pangolin/components/overlays/search/search_overlay.dart';
import 'package:pangolin/components/overlays/tray_overlay.dart';
import 'package:pangolin/components/overlays/welcome_overlay.dart';
import 'package:pangolin/components/shell/shell.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/wm/layout.dart';
import 'package:pangolin/utils/wm/wm.dart';
import 'package:pangolin/components/window/window_decoration.dart' show WindowDecoration;
import 'package:pangolin/components/window/window_decoration.dart' as wd show ResizeEdge;

class Desktop extends StatefulWidget {
  const Desktop({super.key});

  @override
  _DesktopState createState() => _DesktopState();
}

enum SnapZone { none, top, left, right }

class _DesktopState extends State<Desktop> {
  final CompositorWindowService _windowService =
      CompositorWindowService.current;
  final Map<int, Rect> _surfaceRects = {};
  final Map<int, Rect> _restoreRects = {};
  bool _isCompositor = false;
  SnapZone _currentSnapZone = SnapZone.none;
  int? _draggingHandle;
  StreamSubscription<SurfacePositionEvent>? _positionSub;
  StreamSubscription<SurfaceGrabEndEvent>? _grabEndSub;

  static const shellEntry = WindowEntry(
    features: [],
    layoutInfo: FreeformLayoutInfo(
      alwaysOnTop: true,
      alwaysOnTopMode: AlwaysOnTopMode.systemOverlay,
    ),
    properties: {
      WindowEntry.title: "shell",
      WindowExtras.stableId: "shell",
      WindowEntry.showOnTaskbar: false,
      WindowEntry.icon: null,
    },
  );

  @override
  void initState() {
    super.initState();
    _initCompositor();
    ShellService.current.onShellReadyCallback(() {
      if (CustomizationService.current.showWelcomeScreen) {
        ShellService.current.showOverlay("welcome");
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      WindowManagerService.current.push(
        shellEntry.newInstance(
          content: Shell(
            overlays: [
              CompactLauncherOverlay(),
              SearchOverlay(),
              OverviewOverlay(),
              QuickSettingsOverlay(),
              PowerOverlay(),
              AccountOverlay(),
              WelcomeOverlay(),
              NotificationsOverlay(),
              TrayMenuOverlay(),
            ],
          ),
        ),
      );
      // ignore: avoid_print
      print("Initilized Desktop Shell");
    });
  }

  Future<void> _initCompositor() async {
    final bool isCompositor = await Compositor.compositor.isCompositor();
    if (!mounted) return;
    setState(() {
      _isCompositor = isCompositor;
    });
    if (!isCompositor) return;

    _windowService.addListener(_syncWindows);
    _syncWindows();

    _positionSub = _windowService.surfacePositionChanged.listen(_onPositionChanged);
    _grabEndSub = _windowService.surfaceGrabEnded.listen(_onGrabEnded);
  }

  void _onPositionChanged(SurfacePositionEvent event) {
    if (!mounted) return;
    final int handle = event.handle;
    
    // Ignore C position events when Dart is controlling this window via drag.
    // Dart is the source of truth during move/resize operations. C may send
    // stale or incorrect sizes (e.g., surface size without title bar).
    if (_draggingHandle == handle) return;
    
    final Rect current = _surfaceRects[handle] ?? const Rect.fromLTWH(48, 48, 960, 600);
    final double width = event.width > 0 ? event.width.toDouble() : current.width;
    final double height = event.height > 0 ? event.height.toDouble() : current.height;
    setState(() {
      _surfaceRects[handle] = Rect.fromLTWH(
        event.x.toDouble(),
        event.y.toDouble(),
        width,
        height,
      );
    });
  }

  void _onGrabEnded(SurfaceGrabEndEvent event) {
    if (!mounted) return;
    final int handle = event.handle;
    final Offset cursorPos = Offset(event.cursorX, event.cursorY);
    
    setState(() {
      _draggingHandle = null;
      _currentSnapZone = SnapZone.none;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleSnapOnGrabEnd(handle, cursorPos);
    });
  }

  void _handleSnapOnGrabEnd(int handle, Offset cursorPos) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final Size bounds = renderBox.size;
    final double bottomInset = WindowManagerService.current.controller.wmInsets.bottom;
    const double snapEdgeThreshold = 8.0;

    SnapZone zone = SnapZone.none;
    if (cursorPos.dy <= snapEdgeThreshold) {
      zone = SnapZone.top;
    } else if (cursorPos.dx <= snapEdgeThreshold) {
      zone = SnapZone.left;
    } else if (cursorPos.dx >= bounds.width - snapEdgeThreshold) {
      zone = SnapZone.right;
    }

    if (zone == SnapZone.none) return;

    final Rect current = _surfaceRects[handle] ?? const Rect.fromLTWH(48, 48, 960, 600);
    _restoreRects[handle] = current;

    final double maxHeight = math.max(0, bounds.height - bottomInset);
    Rect snapRect;
    switch (zone) {
      case SnapZone.top:
        snapRect = Rect.fromLTWH(0, 0, bounds.width, maxHeight);
        break;
      case SnapZone.left:
        snapRect = Rect.fromLTWH(0, 0, bounds.width / 2, maxHeight);
        break;
      case SnapZone.right:
        snapRect = Rect.fromLTWH(bounds.width / 2, 0, bounds.width / 2, maxHeight);
        break;
      case SnapZone.none:
        return;
    }

    _updateWindowPosition(handle, snapRect);
    setState(() {});

    final windows = _windowService.windows;
    CompositorWindowEntry? entry;
    for (final w in windows) {
      if (w.surface.handle == handle) {
        entry = w;
        break;
      }
    }
    if (entry != null && zone == SnapZone.top) {
      unawaited(_windowService.toggleMaximize(entry.surface, true));
    }
  }

  /// Updates window position in Dart and pushes to C for hit-testing
  void _updateWindowPosition(int handle, Rect rect) {
    _surfaceRects[handle] = rect;
    
    // Push position to C for input hit-testing
    final windows = _windowService.windows;
    for (final w in windows) {
      if (w.surface.handle == handle) {
        unawaited(_windowService.setWindowPosition(
          w.surface,
          rect.left.round(),
          rect.top.round(),
        ));
        break;
      }
    }
  }

  void _syncWindows() {
    if (!mounted) return;
    final List<int> handles =
        _windowService.windows.map((entry) => entry.surface.handle).toList();

    for (final int handle in handles) {
      if (!_surfaceRects.containsKey(handle)) {
        final int index = _surfaceRects.length;
        final double offset = 48 + (index * 24);
        final rect = Rect.fromLTWH(offset, offset, 960, 600);
        _updateWindowPosition(handle, rect);
      }
    }

    _surfaceRects.removeWhere((handle, rect) => !handles.contains(handle));
    _restoreRects.removeWhere((handle, rect) => !handles.contains(handle));

    setState(() {});
  }

  @override
  void dispose() {
    _windowService.removeListener(_syncWindows);
    _positionSub?.cancel();
    _grabEndSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WindowManagerService.current.controller.wmInsets =
        const EdgeInsets.only(bottom: 48);
  }

  Widget _buildCompositorLayer() {
    // Use windowsByZOrder for rendering so windows stack correctly
    final List<CompositorWindowEntry> windows = _windowService.windowsByZOrder;
    if (!_isCompositor || windows.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size bounds = constraints.biggest;
        final double bottomInset =
            WindowManagerService.current.controller.wmInsets.bottom;
        const Size minSize = Size(360, 240);

        Rect clampRect(Rect rect) {
          final double maxHeight = math.max(0, bounds.height - bottomInset);
          final double width = rect.width.clamp(minSize.width, bounds.width);
          final double height = rect.height.clamp(minSize.height, maxHeight);
          final double maxLeft = math.max(0, bounds.width - width);
          final double maxTop = math.max(0, maxHeight - height);
          // Round to integer pixels to prevent 1px jitter between Flutter
          // positioning (sub-pixel) and C hit-testing (integer).
          return Rect.fromLTWH(
            rect.left.clamp(0, maxLeft).roundToDouble(),
            rect.top.clamp(0, maxTop).roundToDouble(),
            width.roundToDouble(),
            height.roundToDouble(),
          );
        }

        const double snapEdgeThreshold = 8.0;

        SnapZone detectSnapZone(Offset globalPosition) {
          if (globalPosition.dy <= snapEdgeThreshold) {
            return SnapZone.top;
          } else if (globalPosition.dx <= snapEdgeThreshold) {
            return SnapZone.left;
          } else if (globalPosition.dx >= bounds.width - snapEdgeThreshold) {
            return SnapZone.right;
          }
          return SnapZone.none;
        }

        Rect snapRectForZone(SnapZone zone) {
          final double maxHeight = math.max(0, bounds.height - bottomInset);
          switch (zone) {
            case SnapZone.top:
              return Rect.fromLTWH(0, 0, bounds.width, maxHeight);
            case SnapZone.left:
              return Rect.fromLTWH(0, 0, bounds.width / 2, maxHeight);
            case SnapZone.right:
              return Rect.fromLTWH(bounds.width / 2, 0, bounds.width / 2, maxHeight);
            case SnapZone.none:
              return Rect.zero;
          }
        }

        void beginMoveSurface(CompositorWindowEntry entry) {
          final int handle = entry.surface.handle;
          _windowService.setActive(handle);
          setState(() {
            _draggingHandle = handle;
          });
          unawaited(_windowService.beginMove(entry.surface));
        }

        int edgeToFlags(wd.ResizeEdge edge) {
          switch (edge) {
            case wd.ResizeEdge.top: return 1;
            case wd.ResizeEdge.bottom: return 2;
            case wd.ResizeEdge.left: return 4;
            case wd.ResizeEdge.right: return 8;
            case wd.ResizeEdge.topLeft: return 1 | 4;
            case wd.ResizeEdge.topRight: return 1 | 8;
            case wd.ResizeEdge.bottomLeft: return 2 | 4;
            case wd.ResizeEdge.bottomRight: return 2 | 8;
          }
        }

        void beginResizeSurfaceFromDecoration(CompositorWindowEntry entry, wd.ResizeEdge edge) {
          final int handle = entry.surface.handle;
          _windowService.setActive(handle);

          if (entry.maximized) {
            final Rect current = _surfaceRects[handle] ?? const Rect.fromLTWH(48, 48, 960, 600);
            _restoreRects[handle] = clampRect(current);
            unawaited(_windowService.toggleMaximize(entry.surface, false));
          }

          unawaited(_windowService.beginResize(entry.surface, edgeToFlags(edge)));
        }

        void moveSurface(CompositorWindowEntry entry, Offset delta, Offset globalPosition) {
          final int handle = entry.surface.handle;
          final SnapZone zone = detectSnapZone(globalPosition);
          
          if (_currentSnapZone != zone || _draggingHandle != handle) {
            setState(() {
              _draggingHandle = handle;
              _currentSnapZone = zone;
            });
          }

          // Directly update the surface position
          final Rect current = _surfaceRects[handle] ?? const Rect.fromLTWH(48, 48, 960, 600);
          final Rect next = current.translate(delta.dx, delta.dy);
          
          _updateWindowPosition(handle, next);
          
          // Force rebuild to update the UI immediately
          setState(() {
             _surfaceRects[handle] = next;
          });
        }

        void onMoveEnd(CompositorWindowEntry entry, Offset globalPosition) {
          setState(() {
            _draggingHandle = null;
            _currentSnapZone = SnapZone.none;
          });
        }

        void resizeSurface(CompositorWindowEntry entry, wd.ResizeEdge edge, Offset delta) {
          final int handle = entry.surface.handle;
          final bool wasMaximized = entry.maximized;
          final Rect current = wasMaximized
              ? clampRect(
                  _restoreRects[handle] ?? Rect.fromLTWH(48, 48, 960, 600),
                )
              : (_surfaceRects[handle] ?? Rect.fromLTWH(48, 48, 960, 600));
          Rect next = current;
          _windowService.setActive(handle);
          if (wasMaximized) {
            unawaited(_windowService.toggleMaximize(entry.surface, false));
          }

          switch (edge) {
            case wd.ResizeEdge.top:
              next = Rect.fromLTRB(
                current.left,
                current.top + delta.dy,
                current.right,
                current.bottom,
              );
              break;
            case wd.ResizeEdge.bottom:
              next = Rect.fromLTRB(
                current.left,
                current.top,
                current.right,
                current.bottom + delta.dy,
              );
              break;
            case wd.ResizeEdge.left:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top,
                current.right,
                current.bottom,
              );
              break;
            case wd.ResizeEdge.right:
              next = Rect.fromLTRB(
                current.left,
                current.top,
                current.right + delta.dx,
                current.bottom,
              );
              break;
            case wd.ResizeEdge.topLeft:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top + delta.dy,
                current.right,
                current.bottom,
              );
              break;
            case wd.ResizeEdge.topRight:
              next = Rect.fromLTRB(
                current.left,
                current.top + delta.dy,
                current.right + delta.dx,
                current.bottom,
              );
              break;
            case wd.ResizeEdge.bottomLeft:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top,
                current.right,
                current.bottom + delta.dy,
              );
              break;
            case wd.ResizeEdge.bottomRight:
              next = Rect.fromLTRB(
                current.left,
                current.top,
                current.right + delta.dx,
                current.bottom + delta.dy,
              );
              break;
          }

          if (next.width < minSize.width) {
            next = Rect.fromLTWH(
              edge == wd.ResizeEdge.left || edge == wd.ResizeEdge.topLeft || edge == wd.ResizeEdge.bottomLeft
                  ? next.right - minSize.width
                  : next.left,
              next.top,
              minSize.width,
              next.height,
            );
          }
          if (next.height < minSize.height) {
            next = Rect.fromLTWH(
              next.left,
              edge == wd.ResizeEdge.top || edge == wd.ResizeEdge.topLeft || edge == wd.ResizeEdge.topRight
                  ? next.bottom - minSize.height
                  : next.top,
              next.width,
              minSize.height,
            );
          }

          next = clampRect(next);
          if (!wasMaximized && next == current) return;
          
          _updateWindowPosition(handle, next);
          
          setState(() {
            _surfaceRects[handle] = next;
            if (wasMaximized) {
              _restoreRects.remove(handle);
            }
          });
        }


        Future<void> toggleMaximize(CompositorWindowEntry entry) async {
          final int handle = entry.surface.handle;
          _windowService.setActive(handle);
          if (entry.maximized) {
            final Rect? restore = _restoreRects.remove(handle);
            if (restore != null) {
              final clampedRestore = clampRect(restore);
              _updateWindowPosition(handle, clampedRestore);
            }
            setState(() {});
            await _windowService.toggleMaximize(entry.surface, false);
            return;
          }

          final Rect current = _surfaceRects[handle] ??
              Rect.fromLTWH(48, 48, 960, 600);
          _restoreRects[handle] = current;
          final maximizedRect = Rect.fromLTWH(
            0,
            0,
            bounds.width,
            math.max(0, bounds.height - bottomInset),
          );
          _updateWindowPosition(handle, maximizedRect);
          setState(() {});
          await _windowService.toggleMaximize(entry.surface, true);
        }

        Future<void> closeSurface(CompositorWindowEntry entry) async {
          await _windowService.close(entry.surface);
        }

        return Stack(
          children: [
            if (_currentSnapZone != SnapZone.none && _draggingHandle != null)
              Positioned.fromRect(
                rect: snapRectForZone(_currentSnapZone),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.5),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            for (final window in windows)
              if (!window.minimized)
                Builder(
                  builder: (context) {
                    final rect = clampRect(
                      _surfaceRects[window.surface.handle] ??
                          const Rect.fromLTWH(48, 48, 960, 600),
                    );
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 16),
                      curve: Curves.linear,
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: RepaintBoundary(
                        child: WindowDecoration(
                          surface: window.surface,
                          title: window.title,
                          isActive: window.active,
                          isMinimized: window.minimized,
                          isMaximized: window.maximized,
                          onActivate: () =>
                              _windowService.setActive(window.surface.handle),
                          onMoveStart: () => beginMoveSurface(window),
                          onMove: (delta, globalPosition) => moveSurface(window, delta, globalPosition),
                          onMoveEnd: (globalPosition) => onMoveEnd(window, globalPosition),
                          onResizeStart: (edge) => beginResizeSurfaceFromDecoration(window, edge),
                          onResize: (edge, delta) => resizeSurface(window, edge, delta),
                          onMinimize: () =>
                              _windowService.toggleMinimize(window.surface.handle),
                          onMaximize: () => toggleMaximize(window),
                          onClose: () => closeSurface(window),
                          child: CompositorSurfaceAutosizeWidget(
                            surface: window.surface,
                            child: SurfaceView(
                              key: ValueKey('surface-${window.surface.handle}'),
                              surface: window.surface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: WallpaperLayer()),
          Positioned.fill(child: _buildCompositorLayer()),
          Positioned.fill(
            child: WindowHierarchy(
              controller: WindowManagerService.current.controller,
              layoutDelegate: const PangolinLayoutDelegate(),
            ),
          ),
        ],
      ),
    );
  }
}
