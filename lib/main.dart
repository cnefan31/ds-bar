import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/theme.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: DsColors.canvas,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MaterialApp(
      title: 'ds-bar',
      debugShowCheckedModeBanner: false,
      theme: DsTheme.build(),
      darkTheme: DsTheme.build(),
      themeMode: ThemeMode.dark,
      home: const DsBarApp(),
    ),
  );
}
