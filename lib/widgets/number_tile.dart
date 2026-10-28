import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/number_item.dart';

/// 列表里的单行：左侧数字 + 右侧「复制」按钮
class NumberTile extends StatelessWidget {
  final NumberItem item;
  const NumberTile({super.key, required this.item});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: item.value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已复制：${item.value}'),
            duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.tag),
      title: Text(item.value,
          style: const TextStyle(fontSize: 18, letterSpacing: 1)),
      trailing: TextButton.icon(
        onPressed: () => _copy(context),
        icon: const Icon(Icons.copy),
        label: const Text('复制'),
      ),
    );
  }
}
