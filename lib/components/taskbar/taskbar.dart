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

import 'package:compositor_dart/compositor_dart.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/widgets/acrylic/acrylic.dart';
import 'package:pangolin/widgets/separated_flex.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';

class Taskbar extends StatefulWidget {
  final List<Widget> leading;
  final List<Widget> center;
  final List<Widget> trailing;
  final bool centerRelativeToScreen;

  const Taskbar({
    this.leading = const [],
    this.center = const [],
    this.trailing = const [],
    this.centerRelativeToScreen = false,
    super.key,
  });

  @override
  State<Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<Taskbar>
    with StateServiceListener<CustomizationService, Taskbar> {
  StreamSubscription<DisplayOutput>? _outputAddedSub;
  StreamSubscription<int>? _outputRemovedSub;
  StreamSubscription<DisplayOutput>? _outputChangedSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to output changes to reposition taskbar
    _outputAddedSub = Compositor.compositor.outputAdded.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _outputRemovedSub = Compositor.compositor.outputRemoved.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _outputChangedSub = Compositor.compositor.outputChanged.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _outputAddedSub?.cancel();
    _outputRemovedSub?.cancel();
    _outputChangedSub?.cancel();
    super.dispose();
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    // Shell is already positioned at primary output, use relative coordinates
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 48,
      child: AcrylicLayer(
        isBackground: true,
        child: SizedBox.expand(
          child: Material(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
            child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        SeparatedFlex(
                          axis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          separator: const SizedBox(width: 4),
                          children: widget.leading,
                        ),
                        Expanded(
                          child: !widget.centerRelativeToScreen
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildCenterGroup(widget.center),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        SeparatedFlex(
                          axis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          separator: const SizedBox(width: 4),
                          children: widget.trailing,
                        ),
                      ],
                    ),
                  ),
                  if (widget.centerRelativeToScreen)
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildCenterGroup(widget.center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildCenterGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: SurfaceLayer(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        outline: false,
        dropShadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}
