import 'package:compositor_dart/compositor_dart.dart';
import 'package:compositor_dart/surface.dart';
import 'package:flutter/material.dart';

/// Resize edge enumeration for window resize operations.
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

/// Unified window decoration widget that enforces consistent styling across ALL
/// Wayland surfaces. This gives the desktop environment a uniform look by forcing
/// rounded corners and consistent title bars on all applications.
///
/// Key features:
/// - 6px rounded corners (configurable via [borderRadius])
/// - Consistent title bar styling
/// - macOS-style window controls
/// - Automatic clipping of child content to rounded corners
class WindowDecoration extends StatelessWidget {
  final Surface surface;
  final String title;
  final bool isActive;
  final bool isMinimized;
  final bool isMaximized;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onActivate;
  final VoidCallback? onMoveStart;
  final void Function(Offset delta, Offset globalPosition)? onMove;
  final void Function(Offset globalPosition)? onMoveEnd;
  final void Function(ResizeEdge edge)? onResizeStart;
  final void Function(ResizeEdge edge, Offset delta)? onResize;

  /// Border radius for window corners. Default is 6.0 pixels.
  /// All windows will be clipped to this radius for visual uniformity.
  static const double borderRadius = 6.0;

  /// Height of the title bar. Default is 38 pixels.
  static const double titleBarHeight = 38.0;

  /// Width of the resize hit area at edges.
  static const double resizeHitBox = 8.0;

  const WindowDecoration({
    super.key,
    required this.surface,
    required this.title,
    required this.isActive,
    required this.isMinimized,
    this.isMaximized = false,
    required this.child,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onActivate,
    this.onMoveStart,
    this.onMove,
    this.onMoveEnd,
    this.onResizeStart,
    this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final hairline = 1.0 / (dpr <= 0 ? 1.0 : dpr);
    final radiusValue = isMaximized ? 0.0 : borderRadius;
    final radius = BorderRadius.circular(radiusValue);
    // Keep the client content inset from the outer stroke so pixels line up.
    // Use a device-pixel hairline inset (0 when maximized/fullscreen-like).
    final contentInset = isMaximized ? 0.0 : hairline;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main window frame with decoration
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withOpacity(0.98),
              borderRadius: radius,
              // macOS-like shadow stack: one soft ambient + one tighter contact.
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isActive ? 0.32 : 0.22),
                  blurRadius: isActive ? 52 : 44,
                  spreadRadius: isActive ? -12 : -14,
                  offset: const Offset(0, 22),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(isActive ? 0.16 : 0.12),
                  blurRadius: isActive ? 18 : 14,
                  spreadRadius: isActive ? -7 : -7,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Title bar
                      _TitleBar(
                        title: title,
                        isActive: isActive,
                        onClose: onClose,
                        onMinimize: onMinimize,
                        onMaximize: onMaximize,
                        onActivate: onActivate,
                        onDragStart: onMoveStart,
                        onDrag: onMove,
                        onDragEnd: onMoveEnd,
                      ),
                      // Crisp separator line under title bar
                      Container(
                        height: hairline,
                        color: Colors.black.withOpacity(isActive ? 0.10 : 0.08),
                      ),
                      // Content area - clipped by compositor for true rounded corners
                      if (!isMinimized)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              contentInset,
                              0,
                              contentInset,
                              contentInset,
                            ),
                            child: child,
                          ),
                        ),
                    ],
                  ),
                  // Crisp outer stroke + inner highlight (macOS feel)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            width: hairline,
                            color: Colors.black.withOpacity(isActive ? 0.22 : 0.18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: EdgeInsets.all(hairline),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(
                              width: hairline,
                              color: Colors.white.withOpacity(isActive ? 0.20 : 0.12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Resize handles
        _buildResizeHandles(),
      ],
    );
  }

  Widget _buildResizeHandles() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Top edge
        Positioned(
          top: 0,
          left: resizeHitBox,
          right: resizeHitBox,
          height: resizeHitBox,
          child: _ResizeHandle(
            edge: ResizeEdge.top,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.top),
            onResize: onResize,
          ),
        ),
        // Bottom edge
        Positioned(
          bottom: 0,
          left: resizeHitBox,
          right: resizeHitBox,
          height: resizeHitBox,
          child: _ResizeHandle(
            edge: ResizeEdge.bottom,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.bottom),
            onResize: onResize,
          ),
        ),
        // Left edge
        Positioned(
          left: 0,
          top: resizeHitBox,
          bottom: resizeHitBox,
          width: resizeHitBox,
          child: _ResizeHandle(
            edge: ResizeEdge.left,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.left),
            onResize: onResize,
          ),
        ),
        // Right edge
        Positioned(
          right: 0,
          top: resizeHitBox,
          bottom: resizeHitBox,
          width: resizeHitBox,
          child: _ResizeHandle(
            edge: ResizeEdge.right,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.right),
            onResize: onResize,
          ),
        ),
        // Corner handles
        Positioned(
          top: 0,
          left: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(
            edge: ResizeEdge.topLeft,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.topLeft),
            onResize: onResize,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(
            edge: ResizeEdge.topRight,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.topRight),
            onResize: onResize,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(
            edge: ResizeEdge.bottomLeft,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.bottomLeft),
            onResize: onResize,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          width: resizeHitBox * 2,
          height: resizeHitBox * 2,
          child: _ResizeHandle(
            edge: ResizeEdge.bottomRight,
            onResizeStart: () => onResizeStart?.call(ResizeEdge.bottomRight),
            onResize: onResize,
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onActivate;
  final VoidCallback? onDragStart;
  final void Function(Offset delta, Offset globalPosition)? onDrag;
  final void Function(Offset globalPosition)? onDragEnd;

  const _TitleBar({
    required this.title,
    required this.isActive,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onActivate,
    this.onDragStart,
    this.onDrag,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SizedBox(
      height: WindowDecoration.titleBarHeight,
      child: Stack(
        children: [
          // Draggable background area
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                onTap: onActivate,
                onDoubleTap: onMaximize,
                onPanStart: (_) => onDragStart?.call(),
                onPanUpdate: (d) => onDrag?.call(d.delta, d.globalPosition),
                onPanEnd: (d) => onDragEnd?.call(d.globalPosition),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Centered title
          Center(
            child: IgnorePointer(
              child: Text(
                title,
                style: TextStyle(
                  color: colors.onSurface.withOpacity(isActive ? 0.85 : 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Window control buttons (macOS-style)
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              // Prevent pan gestures from propagating to title bar
              onPanUpdate: (_) {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WindowControlButton(
                    color: const Color(0xFFFF5F56),
                    hoverColor: const Color(0xFFE04A3F),
                    onTap: onClose,
                  ),
                  const SizedBox(width: 8),
                  _WindowControlButton(
                    color: const Color(0xFFFFBD2E),
                    hoverColor: const Color(0xFFDFA621),
                    onTap: onMinimize,
                  ),
                  const SizedBox(width: 8),
                  _WindowControlButton(
                    color: const Color(0xFF27C93F),
                    hoverColor: const Color(0xFF1AAB32),
                    onTap: onMaximize,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  final Color color;
  final Color hoverColor;
  final VoidCallback? onTap;

  const _WindowControlButton({
    required this.color,
    required this.hoverColor,
    this.onTap,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _isHovered ? widget.hoverColor : widget.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withOpacity(0.08),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ResizeEdge edge;
  final VoidCallback? onResizeStart;
  final void Function(ResizeEdge, Offset)? onResize;

  const _ResizeHandle({
    required this.edge,
    this.onResizeStart,
    required this.onResize,
  });

  MouseCursor _cursorForEdge(ResizeEdge edge) {
    switch (edge) {
      case ResizeEdge.top:
      case ResizeEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeEdge.left:
      case ResizeEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case ResizeEdge.topLeft:
      case ResizeEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeEdge.topRight:
      case ResizeEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursorForEdge(edge),
      child: GestureDetector(
        onPanStart: (_) => onResizeStart?.call(),
        onPanUpdate: (details) => onResize?.call(edge, details.delta),
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
  }
}
