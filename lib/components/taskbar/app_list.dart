import 'package:collection/collection.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/taskbar/taskbar_item.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/wm/properties.dart';
import 'package:xdg_desktop/xdg_desktop.dart';

class AppListElement extends StatefulWidget {
  const AppListElement({super.key});

  @override
  State<AppListElement> createState() => _AppListElementState();
}

class _AppListElementState extends State<AppListElement> {
  CustomizationService get customization => CustomizationService.current;
  WindowManagerService get wm => WindowManagerService.current;
  CompositorWindowService get compositor => CompositorWindowService.current;

  final List<_AppSlot> _slots = [];

  List<String> get _pinnedApps =>
      _slots.where((e) => e.pinned).map((e) => e.id).toList();

  List<String> get _runningApps =>
      _slots.where((e) => e.running).map((e) => e.id).toList();

  @override
  void initState() {
    super.initState();
    _onPinnedAppsChanged();
    _onCurrentEntriesChanged();
    customization.addListener(_onPinnedAppsChanged);
    wm.controller.addListener(_onCurrentEntriesChanged);
    compositor.addListener(_onCompositorChanged);
  }

  @override
  void dispose() {
    customization.removeListener(_onPinnedAppsChanged);
    wm.controller.removeListener(_onCurrentEntriesChanged);
    compositor.removeListener(_onCompositorChanged);
    super.dispose();
  }

  void _onPinnedAppsChanged() {
    if (listEquals(customization.pinnedApps, _pinnedApps)) return;

    final DiffResult<String> diff = calculateListDiff(
      _pinnedApps,
      customization.pinnedApps,
      detectMoves: false,
    );

    for (final DataDiffUpdate<String> update in diff.getUpdatesWithData()) {
      update.when(
        insert: (position, data) {
          // A pinned shortcut refers to an app that can't be found for whatever
          // reason, so we just skip it
          if (ApplicationService.current.getApp(data) == null) return;

          final _AppSlot? runningItem =
              _slots.firstWhereOrNull((e) => e.id == data && e.running);

          if (runningItem != null) {
            final int index = _slots.indexOf(runningItem);
            _slots[index] = runningItem.copyWith(pinned: true);
          } else {
            _slots.add(_AppSlot(id: data, pinned: true, running: false));
          }

          setState(() {});
        },
        remove: (position, data) {
          final _AppSlot? runningItem =
              _slots.firstWhereOrNull((e) => e.id == data && e.running);

          if (runningItem != null) {
            final int index = _slots.indexOf(runningItem);
            _slots[index] = runningItem.copyWith(pinned: false);
          } else {
            _slots.removeWhere((e) => e.id == data);
          }

          setState(() {});
        },
        change: (position, oldData, newData) {},
        move: (from, to, data) {},
      );
    }
  }

  void _onCurrentEntriesChanged() {
    final List<String> entries =
        wm.controller.entries.map((e) => e.registry.extra.appId).toList();

    final DiffResult<String> diff = calculateListDiff(
      _runningApps,
      entries,
      detectMoves: false,
    );

    for (final DataDiffUpdate<String> update in diff.getUpdatesWithData()) {
      update.when(
        insert: (position, data) {
          final _AppSlot? pinnedItem =
              _slots.firstWhereOrNull((e) => e.id == data && e.pinned);

          if (pinnedItem != null) {
            final int index = _slots.indexOf(pinnedItem);
            _slots[index] = pinnedItem.copyWith(running: true);
          } else {
            _slots.add(
              _AppSlot(
                id: data,
                pinned: false,
                running: true,
              ),
            );
          }

          setState(() {});
        },
        remove: (position, data) {
          final _AppSlot? item = _slots.firstWhereOrNull((e) => e.id == data);

          if (item == null) return;

          if (item.pinned) {
            _slots[position] = item.copyWith(running: false);
          } else {
            _slots.remove(item);
          }

          setState(() {});
        },
        change: (position, oldData, newData) {},
        move: (from, to, data) {},
      );
    }
  }

  void _onCompositorChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<CompositorWindowEntry> compositorWindows = compositor.windows;

    return ReorderableListView.builder(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      onReorder: (oldIndex, newIndex) {
        if (oldIndex >= _slots.length) return;

        if (newIndex > _slots.length) {
          newIndex = _slots.length;
        }
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }

        final _AppSlot item = _slots[oldIndex];
        _slots.removeAt(oldIndex);
        _slots.insert(newIndex, item);

        setState(() {});

        if (item.pinned) {
          final bool orderChanged =
              !listEquals(_pinnedApps, customization.pinnedApps);

          if (orderChanged) {
            customization.pinnedApps = _pinnedApps;
          }
        }
      },
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return child;
      },
      itemBuilder: (context, index) {
        if (index < _slots.length) {
          return ReorderableDragStartListener(
            key: ValueKey(_slots[index]),
            index: index,
            child: TaskbarItem(
              entry: ApplicationService.current.getApp(_slots[index].id)!,
            ),
          );
        }

        final CompositorWindowEntry window =
            compositorWindows[index - _slots.length];
        final DesktopEntry? appEntry = window.appId != null
            ? ApplicationService.current.getApp(window.appId!)
            : null;

        return CompositorTaskbarItem(
          key: ValueKey('compositor-${window.surface.handle}'),
          window: window,
          entry: appEntry,
          onTap: () {
            if (window.active && !window.minimized) {
              compositor.toggleMinimize(window.surface.handle);
            } else {
              compositor.setActive(window.surface.handle);
            }
          },
          onClose: () => compositor.close(window.surface),
        );
      },
      itemCount: _slots.length + compositorWindows.length,
    );
  }
}

class _AppSlot {
  final String id;
  final bool pinned;
  final bool running;

  const _AppSlot({
    required this.id,
    required this.pinned,
    required this.running,
  });

  _AppSlot copyWith({
    String? id,
    bool? pinned,
    bool? running,
  }) {
    return _AppSlot(
      id: id ?? this.id,
      pinned: pinned ?? this.pinned,
      running: running ?? this.running,
    );
  }
}
