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

class Desktop extends StatefulWidget {
  const Desktop({super.key});

  @override
  _DesktopState createState() => _DesktopState();
}

class _DesktopState extends State<Desktop> {
  final CompositorWindowService _windowService =
      CompositorWindowService.current;
  final Map<int, Rect> _surfaceRects = {};
  final Map<int, Rect> _restoreRects = {};
  bool _isCompositor = false;

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
  }

  void _syncWindows() {
    if (!mounted) return;
    final List<int> handles =
        _windowService.windows.map((entry) => entry.surface.handle).toList();

    for (final int handle in handles) {
      _surfaceRects.putIfAbsent(
        handle,
        () {
          final int index = _surfaceRects.length;
          final double offset = 48 + (index * 24);
          return Rect.fromLTWH(offset, offset, 960, 600);
        },
      );
    }

    _surfaceRects.removeWhere((handle, rect) => !handles.contains(handle));
    _restoreRects.removeWhere((handle, rect) => !handles.contains(handle));

    setState(() {});
  }

  @override
  void dispose() {
    _windowService.removeListener(_syncWindows);
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
          return Rect.fromLTWH(
            rect.left.clamp(0, maxLeft),
            rect.top.clamp(0, maxTop),
            width,
            height,
          );
        }

        void moveSurface(int handle, Offset delta) {
          final Rect current = _surfaceRects[handle] ??
              Rect.fromLTWH(48, 48, 960, 600);
          final Rect next = clampRect(current.shift(delta));
          if (next == current) return;
          _windowService.setActive(handle);
          setState(() {
            _surfaceRects[handle] = next;
          });
        }

        void resizeSurface(int handle, ResizeEdge edge, Offset delta) {
          final Rect current = _surfaceRects[handle] ??
              Rect.fromLTWH(48, 48, 960, 600);
          Rect next = current;
          _windowService.setActive(handle);

          switch (edge) {
            case ResizeEdge.top:
              next = Rect.fromLTRB(
                current.left,
                current.top + delta.dy,
                current.right,
                current.bottom,
              );
              break;
            case ResizeEdge.bottom:
              next = Rect.fromLTRB(
                current.left,
                current.top,
                current.right,
                current.bottom + delta.dy,
              );
              break;
            case ResizeEdge.left:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top,
                current.right,
                current.bottom,
              );
              break;
            case ResizeEdge.right:
              next = Rect.fromLTRB(
                current.left,
                current.top,
                current.right + delta.dx,
                current.bottom,
              );
              break;
            case ResizeEdge.topLeft:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top + delta.dy,
                current.right,
                current.bottom,
              );
              break;
            case ResizeEdge.topRight:
              next = Rect.fromLTRB(
                current.left,
                current.top + delta.dy,
                current.right + delta.dx,
                current.bottom,
              );
              break;
            case ResizeEdge.bottomLeft:
              next = Rect.fromLTRB(
                current.left + delta.dx,
                current.top,
                current.right,
                current.bottom + delta.dy,
              );
              break;
            case ResizeEdge.bottomRight:
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
              edge == ResizeEdge.left || edge == ResizeEdge.topLeft || edge == ResizeEdge.bottomLeft
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
              edge == ResizeEdge.top || edge == ResizeEdge.topLeft || edge == ResizeEdge.topRight
                  ? next.bottom - minSize.height
                  : next.top,
              next.width,
              minSize.height,
            );
          }

          next = clampRect(next);
          if (next == current) return;
          setState(() {
            _surfaceRects[handle] = next;
          });
        }


        Future<void> toggleMaximize(CompositorWindowEntry entry) async {
          final int handle = entry.surface.handle;
          _windowService.setActive(handle);
          if (entry.maximized) {
            setState(() {
              final Rect? restore = _restoreRects.remove(handle);
              if (restore != null) {
                _surfaceRects[handle] = clampRect(restore);
              }
            });
            await _windowService.toggleMaximize(entry.surface, false);
            return;
          }

          setState(() {
            final Rect current = _surfaceRects[handle] ??
                Rect.fromLTWH(48, 48, 960, 600);
            _restoreRects[handle] = current;
            _surfaceRects[handle] = Rect.fromLTWH(
              0,
              0,
              bounds.width,
              math.max(0, bounds.height - bottomInset),
            );
          });
          await _windowService.toggleMaximize(entry.surface, true);
        }

        Future<void> closeSurface(CompositorWindowEntry entry) async {
          await _windowService.close(entry.surface);
        }

        return Stack(
          children: [
            for (final window in windows)
              if (!window.minimized)
                Positioned.fromRect(
                  rect: clampRect(
                    _surfaceRects[window.surface.handle] ??
                        const Rect.fromLTWH(48, 48, 960, 600),
                  ),
                  child: _FloatingWindowFrame(
                    surface: window.surface,
                    title: window.title,
                    isMinimized: window.minimized,
                    onActivate: () =>
                        _windowService.setActive(window.surface.handle),
                    onMove: (delta) =>
                        moveSurface(window.surface.handle, delta),
                    onResize: (edge, delta) =>
                        resizeSurface(window.surface.handle, edge, delta),
                    onMinimize: () =>
                        _windowService.toggleMinimize(window.surface.handle),
                    onMaximize: () => toggleMaximize(window),
                    onClose: () => closeSurface(window),
                  ),
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

enum ResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _FloatingWindowFrame extends StatelessWidget {
  final Surface surface;
  final String title;
  final bool isMinimized;
  final ValueChanged<Offset> onMove;
  final void Function(ResizeEdge, Offset)? onResize;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onActivate;

  const _FloatingWindowFrame({
    required this.surface,
    required this.title,
    required this.isMinimized,
    required this.onMove,
    required this.onResize,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const double titleBarHeight = 38;
    const double resizeHitBox = 8;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withOpacity(0.98),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.onSurface.withOpacity(0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                SizedBox(
                  height: titleBarHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: onActivate,
                          onPanStart: (_) => onActivate(),
                          onPanUpdate: (details) => onMove(details.delta),
                          behavior: HitTestBehavior.translucent,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      Center(
                        child: IgnorePointer(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: colors.onSurface.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onPanUpdate: (_) {},
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _WindowControlButton(
                                color: const Color(0xFFFF5F56),
                                onTap: onClose,
                              ),
                              const SizedBox(width: 8),
                              _WindowControlButton(
                                color: const Color(0xFFFFBD2E),
                                onTap: onMinimize,
                              ),
                              const SizedBox(width: 8),
                              _WindowControlButton(
                                color: const Color(0xFF27C93F),
                                onTap: onMaximize,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isMinimized)
                  Expanded(
                    child: CompositorSurfaceAutosizeWidget(
                      surface: surface,
                      child: SurfaceView(
                        key: ValueKey('surface-${surface.handle}'),
                        surface: surface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: resizeHitBox,
          right: resizeHitBox,
          height: resizeHitBox,
          child: _ResizeHandle(edge: ResizeEdge.top, onResize: onResize),
        ),
        Positioned(
          bottom: 0,
          left: resizeHitBox,
          right: resizeHitBox,
          height: resizeHitBox,
          child: _ResizeHandle(edge: ResizeEdge.bottom, onResize: onResize),
        ),
        Positioned(
          left: 0,
          top: resizeHitBox,
          bottom: resizeHitBox,
          width: resizeHitBox,
          child: _ResizeHandle(edge: ResizeEdge.left, onResize: onResize),
        ),
        Positioned(
          right: 0,
          top: resizeHitBox,
          bottom: resizeHitBox,
          width: resizeHitBox,
          child: _ResizeHandle(edge: ResizeEdge.right, onResize: onResize),
        ),
        Positioned(
          top: 0,
          left: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(edge: ResizeEdge.topLeft, onResize: onResize),
        ),
        Positioned(
          top: 0,
          right: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(edge: ResizeEdge.topRight, onResize: onResize),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(edge: ResizeEdge.bottomLeft, onResize: onResize),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(edge: ResizeEdge.bottomRight, onResize: onResize),
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _WindowControlButton({
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ResizeEdge edge;
  final void Function(ResizeEdge, Offset)? onResize;

  const _ResizeHandle({
    required this.edge,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onResize?.call(edge, details.delta),
      behavior: HitTestBehavior.translucent,
      child: Container(color: Colors.transparent),
    );
  }
}
