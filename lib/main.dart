import 'package:flutter/material.dart';

import 'overlay_app.dart';
import 'screens/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// 悬浮窗入口（flutter_overlay_window 约定名为 overlayMain）。
/// 必须在顶层并用 @pragma 保证不被裁剪。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '评论数字悬浮窗',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),
      home: const HomePage(),
    );
  }
}
