import 'package:flutter/material.dart';

import 'app_background.dart';

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
    return Hero(
      tag: _routeAppBarHeroTag,
      // Keep the header in the overlay while the route body and its background
      // slide together. Its equal source/destination bounds make the title
      // switch directly instead of drifting with the page.
      transitionOnUserGestures: true,
      flightShuttleBuilder: _buildFlight,
      child: child,
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
    Widget header = AppBackdropGroup(child: destination.child);
    final mediaQuery = MediaQuery.maybeOf(toHeroContext);
    if (mediaQuery != null) {
      header = MediaQuery(data: mediaQuery, child: header);
    }
    return InheritedTheme.captureAll(toHeroContext, header);
  }
}
