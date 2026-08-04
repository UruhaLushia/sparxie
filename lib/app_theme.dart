part of 'main.dart';

class _SystemBarStyle extends StatelessWidget {
  const _SystemBarStyle({required this.child});

  final Widget child;

  static const double _buttonNavThreshold = 40;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return child;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;
    final isButtonNav =
        MediaQuery.viewPaddingOf(context).bottom >= _buttonNavThreshold;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: scheme.brightness,
        systemNavigationBarColor: isButtonNav
            ? scheme.surface
            : Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}

class _ThemeModeTransition extends StatefulWidget {
  const _ThemeModeTransition({
    required this.brightness,
    required this.surfaceColor,
    required this.child,
  });

  final Brightness brightness;
  final Color surfaceColor;
  final Widget child;

  @override
  State<_ThemeModeTransition> createState() => _ThemeModeTransitionState();
}

class _ThemeModeTransitionState extends State<_ThemeModeTransition>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 150);

  AnimationController? _controller;
  var _overlayColor = Colors.transparent;
  var _startOpacity = 0.0;
  var _generation = 0;

  @override
  void didUpdateWidget(_ThemeModeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness == widget.brightness) return;
    _overlayColor = oldWidget.surfaceColor;
    _startOpacity = oldWidget.brightness == Brightness.dark ? 0.18 : 0.12;
    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: _duration,
    );
    final generation = ++_generation;
    controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted ||
          generation != _generation ||
          !identical(_controller, controller) ||
          !controller.isCompleted) {
        return;
      }
      setState(() => _controller = null);
      controller.dispose();
    });
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(child: IgnorePointer(child: _buildOverlay())),
      ],
    );
  }

  Widget _buildOverlay() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(controller.value);
        return ColoredBox(
          color: _overlayColor.withValues(
            alpha: _startOpacity * (1 - progress),
          ),
        );
      },
    );
  }
}

/// Material 3's Android stretch effect transforms the scrollable subtree.
/// Backdrop filters inside that subtree can lose their sampled backdrop until
/// the overscroll gesture ends, so keep Android's normal clamping without the
/// visual stretch. Other platforms retain their native overscroll behavior.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (getPlatform(context) == TargetPlatform.android) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }
}

ThemeData _appTheme({
  required Brightness brightness,
  required Color seedColor,
  required List<String> userFonts,
  required bool useAutomaticColors,
  required bool pureBlack,
  required bool showDividers,
  required AppBackgroundSource backgroundSource,
  required double surfaceOpacity,
  required AppSurfaceEffect surfaceEffect,
  required double surfaceBlur,
}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  scheme = _applyThemeColorCoverage(
    scheme,
    seedColor,
    preserveSeedPrimary: !useAutomaticColors,
  );
  if (pureBlack &&
      brightness == Brightness.dark &&
      backgroundSource == AppBackgroundSource.theme) {
    scheme = _pureBlackScheme(scheme);
  }
  final customBackground = backgroundSource != AppBackgroundSource.theme;
  final surfaceTheme = AppSurfaceTheme(
    enabled: customBackground,
    effect: surfaceEffect,
    blurSigma: surfaceBlur,
    opacity: surfaceOpacity,
    tintColor: seedColor,
  );
  final dividerColor = !showDividers
      ? Colors.transparent
      : scheme.onSurface.withValues(
          alpha: brightness == Brightness.dark ? 0.12 : 0.1,
        );
  final menuSurface = scheme.surfaceContainerHigh;
  const noSurfaceTint = WidgetStatePropertyAll<Color?>(Colors.transparent);
  final menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll<Color?>(menuSurface),
    surfaceTintColor: noSurfaceTint,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: surfaceTheme.pageColor(scheme.surface),
    canvasColor: scheme.surface,
    cardColor: scheme.surfaceContainerLow,
    dividerColor: dividerColor,
    dividerTheme: DividerThemeData(color: dividerColor, thickness: 0.5),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    hoverColor: scheme.primary.withValues(alpha: 0.06),
    highlightColor: scheme.primary.withValues(alpha: 0.08),
    splashColor: scheme.primary.withValues(alpha: 0.1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: surfaceTheme.chromeColor(scheme.surface),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceTheme.modalSurfaceColor(
        scheme.surfaceContainerHigh,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceTheme.modalSurfaceColor(
        scheme.surfaceContainerLow,
      ),
      modalBackgroundColor: surfaceTheme.modalSurfaceColor(
        scheme.surfaceContainerLow,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: menuSurface,
      surfaceTintColor: Colors.transparent,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(menuStyle: menuStyle),
    menuTheme: MenuThemeData(style: menuStyle),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppHorizontalPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: AppHorizontalPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: AppHorizontalPageTransitionsBuilder(),
      },
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
    ),
    extensions: [surfaceTheme],
  );
  final themed = _applyFontSet(base, userFonts);
  return themed.copyWith(
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surfaceTheme.modalSurfaceColor(
        scheme.surfaceContainerHigh,
      ),
      contentTextStyle: themed.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
      actionTextColor: scheme.primary,
      closeIconColor: scheme.onSurfaceVariant,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: kAppPanelRadius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    ),
  );
}

ColorScheme _applyThemeColorCoverage(
  ColorScheme scheme,
  Color seedColor, {
  required bool preserveSeedPrimary,
}) {
  final dark = scheme.brightness == Brightness.dark;
  final neutral = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: scheme.brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  Color tint(Color base, double lightOpacity, double darkOpacity) =>
      Color.alphaBlend(
        seedColor.withValues(alpha: dark ? darkOpacity : lightOpacity),
        base,
      );
  final onSeed =
      ThemeData.estimateBrightnessForColor(seedColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final surface = dark ? neutral.surface : Colors.white;
  final surfaceDim = dark ? tint(neutral.surfaceDim, 0, 0.015) : Colors.white;
  final surfaceBright = dark ? neutral.surfaceBright : Colors.white;
  final surfaceContainerLowest = dark
      ? neutral.surfaceContainerLowest
      : Colors.white;
  final surfaceContainerLow = dark
      ? tint(neutral.surfaceContainerLow, 0, 0.015)
      : tint(Colors.white, 0.01, 0);
  final surfaceContainer = dark
      ? tint(neutral.surfaceContainer, 0, 0.025)
      : tint(Colors.white, 0.025, 0);
  final surfaceContainerHigh = dark
      ? tint(neutral.surfaceContainerHigh, 0, 0.04)
      : tint(Colors.white, 0.04, 0);
  final surfaceContainerHighest = dark
      ? tint(neutral.surfaceContainerHighest, 0, 0.055)
      : tint(Colors.white, 0.06, 0);
  return scheme.copyWith(
    primary: preserveSeedPrimary ? seedColor : scheme.primary,
    onPrimary: preserveSeedPrimary ? onSeed : scheme.onPrimary,
    secondaryContainer: tint(scheme.secondaryContainer, 0.03, 0.05),
    tertiaryContainer: tint(scheme.tertiaryContainer, 0.02, 0.03),
    surface: surface,
    onSurface: neutral.onSurface,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurfaceVariant: neutral.onSurfaceVariant,
    outline: tint(neutral.outline, 0.03, 0.03),
    outlineVariant: tint(neutral.outlineVariant, 0.06, 0.045),
    inverseSurface: neutral.inverseSurface,
    onInverseSurface: neutral.onInverseSurface,
    surfaceTint: seedColor,
  );
}

ColorScheme _pureBlackScheme(ColorScheme scheme) => scheme.copyWith(
  surface: Colors.black,
  surfaceDim: Colors.black,
  surfaceBright: const Color(0xff1c1c1c),
  surfaceContainerLowest: Colors.black,
  surfaceContainerLow: const Color(0xff050505),
  surfaceContainer: const Color(0xff0a0a0a),
  surfaceContainerHigh: const Color(0xff101010),
  surfaceContainerHighest: const Color(0xff181818),
);

ThemeData _applyFontSet(ThemeData base, List<String> userFonts) {
  if (userFonts.isEmpty) return base;
  return base.copyWith(
    textTheme: _applyTextThemeFontSet(base.textTheme, userFonts),
    primaryTextTheme: _applyTextThemeFontSet(base.primaryTextTheme, userFonts),
  );
}

TextTheme _applyTextThemeFontSet(TextTheme theme, List<String> userFonts) {
  return theme.copyWith(
    displayLarge: _applyTextStyleFontSet(theme.displayLarge, userFonts),
    displayMedium: _applyTextStyleFontSet(theme.displayMedium, userFonts),
    displaySmall: _applyTextStyleFontSet(theme.displaySmall, userFonts),
    headlineLarge: _applyTextStyleFontSet(theme.headlineLarge, userFonts),
    headlineMedium: _applyTextStyleFontSet(theme.headlineMedium, userFonts),
    headlineSmall: _applyTextStyleFontSet(theme.headlineSmall, userFonts),
    titleLarge: _applyTextStyleFontSet(theme.titleLarge, userFonts),
    titleMedium: _applyTextStyleFontSet(theme.titleMedium, userFonts),
    titleSmall: _applyTextStyleFontSet(theme.titleSmall, userFonts),
    bodyLarge: _applyTextStyleFontSet(theme.bodyLarge, userFonts),
    bodyMedium: _applyTextStyleFontSet(theme.bodyMedium, userFonts),
    bodySmall: _applyTextStyleFontSet(theme.bodySmall, userFonts),
    labelLarge: _applyTextStyleFontSet(theme.labelLarge, userFonts),
    labelMedium: _applyTextStyleFontSet(theme.labelMedium, userFonts),
    labelSmall: _applyTextStyleFontSet(theme.labelSmall, userFonts),
  );
}

TextStyle? _applyTextStyleFontSet(TextStyle? style, List<String> userFonts) {
  if (style == null) return null;
  final chain = <String>[];
  for (final family in userFonts) {
    if (family == AppPrefs.systemFontFamily) {
      _addSystemFontChain(chain, style);
    } else {
      _addFont(chain, family);
    }
  }
  if (chain.isEmpty) return style;
  final fallback = chain.skip(1).toList();
  return style.copyWith(
    fontFamily: chain.first,
    fontFamilyFallback: fallback.isEmpty ? null : fallback,
  );
}

void _addSystemFontChain(List<String> out, TextStyle style) {
  final family = style.fontFamily;
  if (family != null) _addFont(out, family);
  for (final family in style.fontFamilyFallback ?? const <String>[]) {
    _addFont(out, family);
  }
}

void _addFont(List<String> out, String family) {
  if (!out.contains(family)) out.add(family);
}
