import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/shell/shell.dart';
import 'package:pangolin/utils/data/globals.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';

class ShellServiceFactory extends ServiceFactory<ShellService> {
  const ShellServiceFactory();

  @override
  ShellService build() => _ShellServiceImpl();
}

abstract class ShellService extends ListenableService {
  ShellService();

  static ShellService get current {
    return ServiceManager.getService<ShellService>()!;
  }

  void registerShell(ShellState shell, List<ShellOverlay> overlays);
  void onShellReadyCallback(void Function() callback);
  void notifyStartupComplete();

  Future<void> showOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
    bool dismissEverything = true,
  });

  Future<void> dismissOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
  });

  Future<void> toggleOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
  });

  bool currentlyShown(String overlayId);

  ValueNotifier<bool> getShowingNotifier(String overlayId);

  List<String> get currentlyShownOverlays;

  void dismissEverything();

  void showInformativeDialog(String title, String message);
}

class _ShellServiceImpl extends ShellService {
  late final List<ShellOverlay> overlays;
  ShellState? state;
  bool shellStarted = false;

  final List<void Function()> callbacks = [];

  @override
  void registerShell(ShellState shell, List<ShellOverlay> overlays) {
    if (state != null) throw Exception("Shell already registered");

    state = shell;
    this.overlays = overlays;
  }

  @override
  void onShellReadyCallback(void Function() callback) {
    if (shellStarted) {
      callback();
      return;
    }
    callbacks.add(callback);
  }

  @override
  void notifyStartupComplete() {
    if (shellStarted) throw Exception("Shell already started up and notified");

    shellStarted = true;
    for (final callback in callbacks) {
      callback();
    }
    callbacks.clear();
  }

  @override
  Future<void> showOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
    bool dismissEverything = true,
  }) async {
    final ShellOverlay overlay = overlays.firstWhere((o) => o.id == overlayId);
    if (dismissEverything) this.dismissEverything();
    await overlay._controller.requestShow(args);
  }

  @override
  Future<void> dismissOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
  }) async {
    final ShellOverlay overlay = overlays.firstWhere((o) => o.id == overlayId);
    await overlay._controller.requestDismiss(args);
  }

  @override
  Future<void> toggleOverlay(
    String overlayId, {
    Map<String, dynamic> args = const {},
  }) async {
    if (!currentlyShown(overlayId)) {
      await showOverlay(overlayId, args: args);
    } else {
      await dismissOverlay(overlayId, args: args);
    }
  }

  @override
  bool currentlyShown(String overlayId) {
    final ShellOverlay overlay = overlays.firstWhere((o) => o.id == overlayId);
    return overlay._controller.showing;
  }

  @override
  ValueNotifier<bool> getShowingNotifier(String overlayId) {
    final ShellOverlay overlay = overlays.firstWhere((o) => o.id == overlayId);
    return overlay._controller.showingNotifier;
  }

  @override
  List<String> get currentlyShownOverlays {
    final List<String> shownIds = [];
    for (final ShellOverlay o in overlays) {
      if (o._controller.showing) shownIds.add(o.id);
    }
    return shownIds;
  }

  @override
  void dismissEverything() {
    for (final String id in currentlyShownOverlays) {
      dismissOverlay(id);
    }
    state?.notify();
    notifyListeners();
  }

  @override
  void showInformativeDialog(String title, String message) =>
      state?.showInformativeDialog(title, message);

  @override
  FutureOr<void> start() {}

  @override
  FutureOr<void> stop() {
    overlays.clear();
    callbacks.clear();
    shellStarted = false;
  }
}

class ShellOverlayController<T extends ShellOverlayState> {
  T? _overlay;
  final ValueNotifier<bool> showingNotifier = ValueNotifier(false);

  bool get showing => showingNotifier.value;
  set showing(bool value) => showingNotifier.value = value;

  Future<void> requestShow(Map<String, dynamic> args) async {
    _requireOverlayConnection();
    await _overlay!.requestShow(args);
  }

  Future<void> requestDismiss(Map<String, dynamic> args) async {
    _requireOverlayConnection();
    await _overlay!.requestDismiss(args);
  }

  void _requireOverlayConnection() {
    if (_overlay == null) {
      throw Exception(
        "The controller is not connected to any overlay or it had no time to connect yet.",
      );
    }
  }
}

abstract class ShellOverlay extends StatefulWidget {
  final String id;
  final ShellOverlayController _controller = ShellOverlayController();

  ShellOverlay({
    required this.id,
    super.key,
  });

  @override
  ShellOverlayState createState();
}

abstract class ShellOverlayState<T extends ShellOverlay> extends State<T>
    with TickerProviderStateMixin {
  late final AnimationController animationController = AnimationController(
    vsync: this,
    duration: Constants.animationDuration,
  );
  ShellOverlayController get controller => widget._controller;

  Animation<double> get animation => CurvedAnimation(
        parent: animationController,
        curve: Constants.animationCurve,
      );

  @override
  void initState() {
    controller._overlay = this;
    controller.showingNotifier.addListener(_showListener);
    // Ensure rebuild when animation completes dismissal
    animationController.addStatusListener(_animationStatusListener);
    super.initState();
  }

  @override
  void dispose() {
    controller.showingNotifier.removeListener(_showListener);
    animationController.removeStatusListener(_animationStatusListener);
    animationController.dispose();
    super.dispose();
  }

  FutureOr<void> requestShow(Map<String, dynamic> args);

  FutureOr<void> requestDismiss(Map<String, dynamic> args);

  void _showListener() {
    setState(() {});
  }

  void _animationStatusListener(AnimationStatus status) {
    // Force rebuild when animation completes to ensure shouldHide is evaluated
    if (status == AnimationStatus.dismissed || status == AnimationStatus.completed) {
      if (mounted) setState(() {});
    }
  }

  bool get shouldHide => !controller.showing && animationController.value == 0;

  /// Standard implementation for showing overlay with animation.
  /// Subclasses can override requestShow and call this, or implement their own.
  void showWithAnimation() {
    controller.showing = true;
    animationController.forward();
  }

  /// Standard implementation for dismissing overlay with animation.
  /// Subclasses can override requestDismiss and call this, or implement their own.
  void dismissWithAnimation() {
    animationController.reverse();
    controller.showing = false;
  }
}

/// A scaffold widget for dismissible overlays that handles:
/// - Background tap-to-dismiss
/// - Proper hit testing (clicks on content don't dismiss)
/// - Fade and scale animations
/// - Automatic hiding when shouldHide is true
///
/// Usage:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return DismissibleOverlayScaffold(
///     shouldHide: shouldHide,
///     animation: animation,
///     onDismiss: () => controller.requestDismiss({}),
///     width: 600,
///     height: 500,
///     child: _buildContent(context),
///   );
/// }
/// ```
class DismissibleOverlayScaffold extends StatelessWidget {
  final bool shouldHide;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final double width;
  final double height;
  final Widget child;
  final OutlinedBorder? shape;

  const DismissibleOverlayScaffold({
    super.key,
    required this.shouldHide,
    required this.animation,
    required this.onDismiss,
    required this.width,
    required this.height,
    required this.child,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    if (shouldHide) return const SizedBox();

    return Stack(
      children: [
        // Background tap-to-dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // Centered content
        Positioned(
          left: horizontalPadding(context, width),
          right: horizontalPadding(context, width),
          top: verticalPadding(context, height),
          bottom: verticalPadding(context, height),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation,
              alignment: FractionalOffset.center,
              child: GestureDetector(
                // Absorb taps on content to prevent dismiss
                onTap: () {},
                child: SurfaceLayer(
                  outline: true,
                  shape: shape ?? Constants.bigShape,
                  child: Material(
                    type: MaterialType.transparency,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
