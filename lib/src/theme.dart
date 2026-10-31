import 'package:flutter/material.dart';

/// 深色 SaaS 风格 token：近黑画布 + 逐级提亮表面 + hairline 分隔 + 单一强调色。
class DsColors {
  static const canvas = Color(0xFF010102);
  static const surface1 = Color(0xFF0F1011);
  static const surface2 = Color(0xFF141516);
  static const surface3 = Color(0xFF18191A);

  static const hairline = Color(0xFF23252A);
  static const hairlineStrong = Color(0xFF34343A);

  static const ink = Color(0xFFF7F8F8);
  static const inkMuted = Color(0xFFD0D6E0);
  static const inkSubtle = Color(0xFF8A8F98);
  static const inkTertiary = Color(0xFF62666D);

  static const primary = Color(0xFF5E6AD2);
  static const primaryHover = Color(0xFF828FFF);
  static const success = Color(0xFF27A644);
  static const warning = Color(0xFFD9A03A);
  static const danger = Color(0xFFE5484D);
}

/// 字号阶梯。跨级明显（52 → 14 → 10.5），保证一级视觉只有一个。
class DsText {
  /// 余额主数字。全页唯一的一级视觉。
  static const hero = TextStyle(
    fontSize: 52,
    fontWeight: FontWeight.w600,
    letterSpacing: -2.4,
    height: 1.0,
    color: DsColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 主数字的币种符号，降一级。
  static const heroSym = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
    color: DsColors.inkSubtle,
  );

  /// 空态标题。
  static const emptyTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: DsColors.ink,
  );

  /// 指标值（14sp）。
  static const metric = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: DsColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 列表主行（12.5sp）。
  static const rowTitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: DsColors.ink,
  );

  /// 列表次行（10.5sp），等宽数字。
  static const rowSub = TextStyle(
    fontSize: 10.5,
    height: 1.5,
    color: DsColors.inkTertiary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 分区标题（11.5sp / 600）。
  static const section = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: DsColors.inkMuted,
  );

  /// 分区标题旁的灰色注记。
  static const sectionNote = TextStyle(
    fontSize: 10.5,
    color: DsColors.inkTertiary,
  );

  /// 指标小标签（9.5sp）。
  static const metricLabel = TextStyle(
    fontSize: 9.5,
    letterSpacing: 0.2,
    color: DsColors.inkTertiary,
  );

  /// 说明文字（10.5sp）。
  static const hint = TextStyle(
    fontSize: 10.5,
    height: 1.65,
    color: DsColors.inkTertiary,
  );

  /// 等宽金额。
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 间距阶梯。全站只用这几档，避免随手数字。
class DsSpace {
  /// 卡片内边距。
  static const cardPad = EdgeInsets.symmetric(horizontal: 12, vertical: 11);

  /// 屏内容左右边距。
  static const screenH = 16.0;

  /// 分区标题上间距（标题与上一块的距离）。
  static const sectionTop = 22.0;

  /// 分区标题下间距（标题与内容块的距离）。
  static const sectionBottom = 10.0;

  /// 紧邻块之间。
  static const tight = 8.0;

  /// 常规块之间。
  static const normal = 14.0;
}

class DsTheme {
  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: DsColors.primary,
      onPrimary: Colors.white,
      secondary: DsColors.primary,
      surface: DsColors.surface1,
      onSurface: DsColors.ink,
      error: DsColors.danger,
      onError: Colors.white,
      outline: DsColors.hairline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: DsColors.canvas,
      canvasColor: DsColors.canvas,
      dividerColor: DsColors.hairline,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.0,
          color: DsColors.ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: DsColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          color: DsColors.ink,
        ),
        bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: DsColors.inkMuted),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: DsColors.inkSubtle),
        labelSmall: TextStyle(fontSize: 11, letterSpacing: 0.6, color: DsColors.inkSubtle),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: DsColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: DsColors.ink,
        ),
        iconTheme: IconThemeData(color: DsColors.inkMuted, size: 20),
      ),
      cardTheme: const CardThemeData(
        color: DsColors.surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DsColors.surface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: DsColors.inkTertiary, fontSize: 13),
        labelStyle: const TextStyle(color: DsColors.inkSubtle, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DsColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DsColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DsColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DsColors.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DsColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DsColors.ink,
          side: const BorderSide(color: DsColors.hairlineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DsColors.inkMuted,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return DsColors.inkTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return DsColors.primary;
          return DsColors.surface3;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(DsColors.hairlineStrong),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: DsColors.primary,
        labelColor: DsColors.ink,
        unselectedLabelColor: DsColors.inkSubtle,
        dividerColor: DsColors.hairline,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DsColors.canvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: DsColors.surface3,
        elevation: 0,
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? DsColors.ink : DsColors.inkSubtle,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 21,
            color: selected ? DsColors.primaryHover : DsColors.inkSubtle,
          );
        }),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: DsColors.surface3,
        contentTextStyle: TextStyle(color: DsColors.ink, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: DsColors.inkSubtle,
        textColor: DsColors.ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  /// 数字用等宽字体，避免金额跳动。
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
