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
import 'package:flutter/material.dart';
import 'package:pangolin/services/shell.dart';

class DisplaySettingsOverlay extends ShellOverlay {
  static const String overlayId = "display_settings";

  DisplaySettingsOverlay({super.key}) : super(id: overlayId);

  @override
  _DisplaySettingsOverlayState createState() => _DisplaySettingsOverlayState();
}

class _DisplaySettingsOverlayState
    extends ShellOverlayState<DisplaySettingsOverlay> {
  Map<int, DisplayOutput> _outputs = {};
  int? _selectedOutputId;
  DisplayMode? _pendingMode;
  int _vsyncOption = 0; // 0 = auto, >0 = specific output id, -1 = power saver

  StreamSubscription<DisplayOutput>? _outputAddedSub;
  StreamSubscription<int>? _outputRemovedSub;
  StreamSubscription<DisplayOutput>? _outputChangedSub;

  @override
  void initState() {
    super.initState();

    _outputs = Map.from(Compositor.compositor.outputs);
    if (_outputs.isNotEmpty) {
      _selectedOutputId = _outputs.values.first.id;
    }

    _outputAddedSub = Compositor.compositor.outputAdded.stream.listen((output) {
      if (!mounted) return;
      setState(() {
        _outputs[output.id] = output;
        _selectedOutputId ??= output.id;
      });
    });

    _outputRemovedSub =
        Compositor.compositor.outputRemoved.stream.listen((id) {
      if (!mounted) return;
      setState(() {
        _outputs.remove(id);
        if (_selectedOutputId == id) {
          _selectedOutputId = _outputs.isNotEmpty ? _outputs.keys.first : null;
        }
      });
    });

    _outputChangedSub =
        Compositor.compositor.outputChanged.stream.listen((output) {
      if (!mounted) return;
      setState(() {
        _outputs[output.id] = output;
      });
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
  FutureOr<void> requestShow(Map<String, dynamic> args) {
    showWithAnimation();
  }

  @override
  FutureOr<void> requestDismiss(Map<String, dynamic> args) {
    dismissWithAnimation();
  }

  DisplayOutput? get _selectedOutput =>
      _selectedOutputId != null ? _outputs[_selectedOutputId] : null;

  Future<void> _applySettings() async {
    final output = _selectedOutput;
    if (output == null) return;

    final errors = <String>[];

    // Apply pending mode if changed
    if (_pendingMode != null) {
      final success = await Compositor.compositor.setOutputMode(output.id, _pendingMode!);
      if (success) {
        _pendingMode = null;
      } else {
        errors.add('Failed to set display mode');
      }
    }

    // Apply vsync setting
    if (_vsyncOption == -1) {
      // Power saver mode - cap at 60Hz
      if (!await Compositor.compositor.setVsyncRateLimit(60)) {
        errors.add('Failed to set vsync rate limit');
      }
      if (!await Compositor.compositor.setVsyncOutput(0)) {
        errors.add('Failed to set vsync output');
      }
    } else {
      if (!await Compositor.compositor.setVsyncRateLimit(0)) {
        errors.add('Failed to set vsync rate limit');
      }
      if (!await Compositor.compositor.setVsyncOutput(_vsyncOption)) {
        errors.add('Failed to set vsync output');
      }
    }

    // Log errors (SnackBar requires Scaffold which overlays may not have)
    if (errors.isNotEmpty) {
      print('Display settings errors: ${errors.join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissibleOverlayScaffold(
      shouldHide: shouldHide,
      animation: animation,
      onDismiss: () => controller.requestDismiss({}),
      width: 600,
      height: 500,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          color: colorScheme.surface,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Display Settings",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Configure your displays",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_outputs.isEmpty)
                  Center(
                    child: Text(
                      "No displays detected",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                else ...[
                  // Display visual representation
                  _buildDisplayPreview(context),
                  const SizedBox(height: 24),

                  // Display selector
                  if (_outputs.length > 1) ...[
                    Text(
                      "Select Display",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _outputs.values.map((output) {
                        final isSelected = output.id == _selectedOutputId;
                        return ChoiceChip(
                          label: Text(output.name),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedOutputId = output.id);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Selected display settings
                  if (_selectedOutput != null) ...[
                    _buildOutputSettings(context, _selectedOutput!),
                    const SizedBox(height: 24),
                  ],

                  // Vsync settings
                  _buildVsyncSettings(context),
                ],
              ],
            ),
          ),
        ),

        // Footer with buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => controller.requestDismiss({}),
                child: const Text("Cancel"),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await _applySettings();
                  controller.requestDismiss({});
                },
                child: const Text("Apply"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayPreview(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate bounds for scaling
    if (_outputs.isEmpty) return const SizedBox();

    int minX = _outputs.values.map((o) => o.x).reduce((a, b) => a < b ? a : b);
    int minY = _outputs.values.map((o) => o.y).reduce((a, b) => a < b ? a : b);
    int maxX = _outputs.values
        .map((o) => o.x + o.width)
        .reduce((a, b) => a > b ? a : b);
    int maxY = _outputs.values
        .map((o) => o.y + o.height)
        .reduce((a, b) => a > b ? a : b);

    final totalWidth = (maxX - minX).toDouble();
    final totalHeight = (maxY - minY).toDouble();
    final scale = totalWidth > 0 ? 300.0 / totalWidth : 1.0;

    return Container(
      height: totalHeight * scale + 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: _outputs.values.map((output) {
          final isSelected = output.id == _selectedOutputId;
          final x = (output.x - minX) * scale + 20;
          final y = (output.y - minY) * scale + 20;
          final w = output.width * scale;
          final h = output.height * scale;

          return Positioned(
            left: x,
            top: y,
            width: w,
            height: h,
            child: GestureDetector(
              onTap: () => setState(() => _selectedOutputId = output.id),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surface,
                  border: Border.all(
                    color:
                        isSelected ? colorScheme.primary : colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        output.name,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "${output.width}x${output.height}",
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOutputSettings(BuildContext context, DisplayOutput output) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Group modes by resolution
    final Map<String, List<DisplayMode>> modesByResolution = {};
    for (final mode in output.availableModes) {
      final key = "${mode.width}x${mode.height}";
      modesByResolution.putIfAbsent(key, () => []).add(mode);
    }

    final resolutions = modesByResolution.keys.toList();
    final currentResolution = "${output.width}x${output.height}";
    final currentRefresh = output.refreshRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Display: ${output.name}",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        if (output.make.isNotEmpty || output.model.isNotEmpty)
          Text(
            "${output.make} ${output.model}".trim(),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),

        // Resolution dropdown
        Text("Resolution", style: TextStyle(color: colorScheme.onSurface)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: resolutions.contains(currentResolution)
              ? currentResolution
              : (resolutions.isNotEmpty ? resolutions.first : null),
          isExpanded: true,
          items: resolutions.map((res) {
            return DropdownMenuItem(
              value: res,
              child: Text(res),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null && modesByResolution[value] != null) {
              // Select highest refresh rate for this resolution
              final modes = modesByResolution[value]!;
              modes.sort((a, b) => b.refresh.compareTo(a.refresh));
              setState(() => _pendingMode = modes.first);
            }
          },
        ),
        const SizedBox(height: 16),

        // Refresh rate dropdown
        Text("Refresh Rate", style: TextStyle(color: colorScheme.onSurface)),
        const SizedBox(height: 4),
        DropdownButton<int>(
          value: _pendingMode?.refresh ?? currentRefresh,
          isExpanded: true,
          items: (modesByResolution[_pendingMode != null
                      ? "${_pendingMode!.width}x${_pendingMode!.height}"
                      : currentResolution] ??
                  [])
              .map((mode) {
            return DropdownMenuItem(
              value: mode.refresh,
              child: Text("${mode.refreshHz.toStringAsFixed(0)} Hz"),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              final res = _pendingMode != null
                  ? "${_pendingMode!.width}x${_pendingMode!.height}"
                  : currentResolution;
              final modes = modesByResolution[res] ?? [];
              final mode = modes.firstWhere(
                (m) => m.refresh == value,
                orElse: () => modes.first,
              );
              setState(() => _pendingMode = mode);
            }
          },
        ),

        if (output.isPrimary) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.star, size: 16, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                "Primary display",
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVsyncSettings(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Animation Sync",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Select which display drives animations",
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _vsyncOption,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: 0,
              child: Text("Auto (highest refresh rate)"),
            ),
            ..._outputs.values.map((output) {
              return DropdownMenuItem(
                value: output.id,
                child: Text(
                    "${output.name} (${output.refreshHz.toStringAsFixed(0)} Hz)"),
              );
            }),
            const DropdownMenuItem(
              value: -1,
              child: Text("Power saver (60 Hz cap)"),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _vsyncOption = value);
            }
          },
        ),
      ],
    );
  }
}
