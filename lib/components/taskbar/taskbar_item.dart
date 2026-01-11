import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/utils/wm/wm.dart';
import 'package:pangolin/widgets/context_menu.dart';
import 'package:pangolin/widgets/resource/auto_image.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:xdg_desktop/xdg_desktop.dart';
import 'package:yatl_flutter/yatl_flutter.dart';

class TaskbarItem extends StatefulWidget {
  final DesktopEntry entry;

  const TaskbarItem({required this.entry, super.key});

  @override
  _TaskbarItemState createState() => _TaskbarItemState();
}

class _TaskbarItemState extends State<TaskbarItem>
    with
        SingleTickerProviderStateMixin,
        StateServiceListener<CustomizationService, TaskbarItem> {
  late AnimationController _ac;
  late Animation<double> _anim;
  bool _hovering = false;
  bool _previewHovering = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _anim = CurvedAnimation(
      parent: _ac,
      curve: Curves.ease,
      reverseCurve: Curves.ease,
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    _removeTooltip();
    super.dispose();
  }

  void _showTooltip() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: MouseRegion(
            onEnter: (_) {
              _previewHovering = true;
            },
            onExit: (_) {
              _previewHovering = false;
              _maybeRemoveTooltip();
            },
            child: _TaskbarItemPreview(
              title: widget.entry.name.resolve(context.locale),
              iconResource: widget.entry.icon?.main,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _maybeRemoveTooltip() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_hovering && !_previewHovering) {
        _removeTooltip();
      }
    });
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    final hierarchy = WindowManagerService.current.controller;
    final windows = hierarchy.entries;
    final bool appIsRunning = windows.any(
      (element) => element.registry.extra.appId == widget.entry.id,
    );
    final LiveWindowEntry? entry = appIsRunning
        ? windows.firstWhere(
            (element) => element.registry.extra.appId == widget.entry.id,
          )
        : null;
    final LiveWindowEntry? focusedEntry = appIsRunning
        ? windows.firstWhere(
            (element) =>
                element.registry.extra.appId ==
                hierarchy.sortedEntries.last.registry.extra.appId,
          )
        : null;
    final bool focused = windows.length > 1 &&
        (focusedEntry?.registry.extra.appId == widget.entry.id &&
            !windows.last.layoutState.minimized);

    final bool showSelected =
        appIsRunning && focused && !entry!.layoutState.minimized;

    if (showSelected) {
      _ac.animateTo(1);
    } else {
      _ac.animateBack(0);
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
        child: SizedBox(
          height: 36,
          width: 36,
          child: ContextMenu(
            entries: [
              ContextMenuItem(
                leading: const Icon(Icons.info_outline_rounded),
                child: Text(widget.entry.name.resolve(context.locale)),
                onTap: () {},
              ),
              ContextMenuItem(
                leading: const Icon(Icons.push_pin_outlined),
                child: Text(
                  service.pinnedApps.contains(widget.entry.id)
                      ? "Unpin from Taskbar"
                      : "Pin to Taskbar",
                ),
                onTap: () {
                  service.togglePinnedApp(widget.entry.id);
                },
              ),
              if (appIsRunning)
                ContextMenuItem(
                  leading: const Icon(Icons.close_outlined),
                  child: const Text("Close Window"),
                  onTap: () =>
                      WindowManagerService.current.pop(entry!.registry.info.id),
                ),
            ],
            child: Material(
              borderRadius: BorderRadius.circular(8),
              color: showSelected
                  ? colors.secondary.withOpacity(0.18)
                  : _hovering
                      ? colors.onSurface.withOpacity(0.08)
                      : Colors.transparent,
              child: InkWell(
                onHover: (value) {
                  _hovering = value;
                  if (value) {
                    _showTooltip();
                  } else {
                    _maybeRemoveTooltip();
                  }
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (appIsRunning) {
                    _onTap(context, entry!);
                  } else {
                    ApplicationService.current.startApp(widget.entry.id);
                  }
                },
                child: Center(
                  child: appIsRunning
                      ? (entry?.registry.info.icon != null
                          ? Image(
                              image: entry!.registry.info.icon!,
                              width: 28,
                              height: 28,
                            )
                          : AutoVisualResource(
                              resource: widget.entry.icon?.main ?? "",
                              size: 28,
                            ))
                      : AutoVisualResource(
                          resource: widget.entry.icon?.main ?? "",
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, LiveWindowEntry entry) {
    final hierarchy = WindowHierarchy.of(context, listen: false);
    final windows = hierarchy.entriesByFocus;

    final bool focused = hierarchy.isFocused(entry.registry.info.id);
    setState(() {});
    if (focused && !entry.layoutState.minimized) {
      entry.layoutState.minimized = true;
      if (windows.length > 1) {
        hierarchy.requestEntryFocus(
          windows[windows.length - 2].registry.info.id,
        );
      }
      setState(() {});
    } else {
      entry.layoutState.minimized = false;
      hierarchy.requestEntryFocus(entry.registry.info.id);
      setState(() {});
    }
  }
}

class CompositorTaskbarItem extends StatefulWidget {
  final CompositorWindowEntry window;
  final DesktopEntry? entry;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const CompositorTaskbarItem({
    required this.window,
    required this.entry,
    required this.onTap,
    required this.onClose,
    super.key,
  });

  @override
  State<CompositorTaskbarItem> createState() => _CompositorTaskbarItemState();
}

class _CompositorTaskbarItemState extends State<CompositorTaskbarItem>
    with StateServiceListener<CustomizationService, CompositorTaskbarItem> {
  bool _hovering = false;
  bool _previewHovering = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _showTooltip() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: MouseRegion(
            onEnter: (_) {
              _previewHovering = true;
            },
            onExit: (_) {
              _previewHovering = false;
              _maybeRemoveTooltip();
            },
            child: _TaskbarItemPreview(
              title: widget.window.title,
              iconResource: widget.entry?.icon?.main,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _maybeRemoveTooltip() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_hovering && !_previewHovering) {
        _removeTooltip();
      }
    });
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Only show as active if this is THE focused window (not just running)
    final bool active = widget.window.active && !widget.window.minimized;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
        child: SizedBox(
          height: 36,
          width: 36,
          child: Material(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? colors.secondary.withOpacity(0.18)
                : _hovering
                    ? colors.onSurface.withOpacity(0.08)
                    : Colors.transparent,
            child: InkWell(
              onHover: (value) {
                _hovering = value;
                if (value) {
                  _showTooltip();
                } else {
                  _maybeRemoveTooltip();
                }
                setState(() {});
              },
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onTap,
              child: Center(
                child: _TaskbarIcon(
                    entry: widget.entry, color: colors.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskbarIcon extends StatelessWidget {
  final DesktopEntry? entry;
  final Color color;

  const _TaskbarIcon({
    required this.entry,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (entry?.icon != null) {
      return AutoVisualResource(
        resource: entry!.icon!.main,
        size: 28,
      );
    }

    return Icon(
      Icons.apps,
      size: 22,
      color: color,
    );
  }
}

class _TaskbarItemPreview extends StatelessWidget {
  final String title;
  final String? iconResource;

  const _TaskbarItemPreview({
    required this.title,
    this.iconResource,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceLayer(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      outline: true,
      dropShadow: true,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 96,
              width: 180,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.grid_view_rounded,
                size: 28,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (iconResource != null) ...[
                  AutoVisualResource(resource: iconResource!, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
