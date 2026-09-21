import 'package:flutter/material.dart';

class WideFloatingNavigationScope extends InheritedWidget {
  const WideFloatingNavigationScope({
    super.key,
    required this.contentInset,
    required super.child,
  });

  final double contentInset;

  static WideFloatingNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WideFloatingNavigationScope>();

  @override
  bool updateShouldNotify(WideFloatingNavigationScope oldWidget) =>
      contentInset != oldWidget.contentInset;
}

class _RouteAppBarHeroTag {
  const _RouteAppBarHeroTag();
}

const _routeAppBarHeroTag = _RouteAppBarHeroTag();

/// Keeps page chrome outside the platform route transition while the body
/// continues to use Flutter's native animation.
class AppRouteAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppRouteAppBar({super.key, required this.child});

  final PreferredSizeWidget child;

  static Widget? leadingOf(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null && !route.isFirst ? const BackButton() : null;
  }

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    final floatingNavigation = WideFloatingNavigationScope.maybeOf(context);
    final header = floatingNavigation == null
        ? child
        : LayoutBuilder(
            builder: (context, constraints) => OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: constraints.maxWidth + floatingNavigation.contentInset,
              maxWidth: constraints.maxWidth + floatingNavigation.contentInset,
              child: Transform.translate(
                offset: Offset(-floatingNavigation.contentInset, 0),
                child: SizedBox(
                  width: constraints.maxWidth + floatingNavigation.contentInset,
                  child: child,
                ),
              ),
            ),
          );
    return Hero(
      tag: _routeAppBarHeroTag,
      // Keep the header in the overlay while the route body and its background
      // slide together. Its equal source/destination bounds make the title
      // switch directly instead of drifting with the page.
      transitionOnUserGestures: true,
      flightShuttleBuilder: _buildFlight,
      child: header,
    );
  }

  static Widget _buildFlight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final destination = toHeroContext.widget as Hero;
    Widget header = destination.child;
    final mediaQuery = MediaQuery.maybeOf(toHeroContext);
    if (mediaQuery != null) {
      header = MediaQuery(data: mediaQuery, child: header);
    }
    return InheritedTheme.captureAll(toHeroContext, header);
  }
}
