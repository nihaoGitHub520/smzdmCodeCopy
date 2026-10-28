import 'package:flutter/material.dart';
import 'screens/home_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '评论数字提取器',
      // smzdm 品牌色偏橙，这里用橙色主题
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
