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
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: _TaskbarItemPreview(
            title: widget.entry.name.resolve(context.locale),
            iconResource: widget.entry.icon?.main,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
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

    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
        child: SizedBox(
          height: 44,
          width: 44,
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
              borderRadius: BorderRadius.circular(4),
              color: appIsRunning
                  ? (showSelected
                      ? Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.15)
                      : Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(0.0))
                  : Colors.transparent,
              child: InkWell(
                onHover: (value) {
                  _hovering = value;
                  if (value) {
                    _showTooltip();
                  } else {
                    _removeTooltip();
                  }
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  if (appIsRunning) {
                    _onTap(context, entry!);
                  } else {
                    ApplicationService.current.startApp(widget.entry.id);
                  }
                },
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, child) {
                    return Stack(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: appIsRunning
                                ? (entry?.registry.info.icon != null
                                    ? Image(
                                        image: entry!.registry.info.icon!,
                                      )
                                    : AutoVisualResource(
                                        resource: widget.entry.icon?.main ??
                                            "",
                                        size: 32,
                                      ))
                                : AutoVisualResource(
                                    resource: widget.entry.icon?.main ?? "",
                                    size: 32,
                                  ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.ease,
                          bottom: 0,
                          left: appIsRunning
                              ? _hovering
                                  ? 8
                                  : showSelected
                                      ? 8
                                      : 14
                              : 22,
                          right: appIsRunning
                              ? _hovering
                                  ? 8
                                  : showSelected
                                      ? 8
                                      : 14
                              : 22,
                          height: 3,
                          child: Material(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    );
                  },
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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _showTooltip() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: _TaskbarItemPreview(
            title: widget.window.title,
            iconResource: widget.entry?.icon?.main,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool active = widget.window.active && !widget.window.minimized;

    final Color backgroundColor = active
        ? colors.secondary.withOpacity(0.15)
        : _hovering
            ? colors.onSurface.withOpacity(0.06)
            : Colors.transparent;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
        child: SizedBox(
          height: 44,
          width: 44,
          child: Material(
            borderRadius: BorderRadius.circular(4),
            color: backgroundColor,
            child: InkWell(
              onHover: (value) {
                _hovering = value;
                if (value) {
                  _showTooltip();
                } else {
                  _removeTooltip();
                }
                setState(() {});
              },
              borderRadius: BorderRadius.circular(4),
              onTap: widget.onTap,
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _TaskbarIcon(
                          entry: widget.entry, color: colors.onSurface),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.ease,
                    bottom: 0,
                    left: active ? 8 : 14,
                    right: active ? 8 : 14,
                    height: 3,
                    child: Material(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(2)),
                      color: colors.secondary.withOpacity(
                          widget.window.minimized
                              ? 0.5
                              : 1.0),
                    ),
                  ),
                ],
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
        size: 26,
      );
    }

    return Icon(
      Icons.apps,
      size: 24,
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
