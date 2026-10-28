import 'package:flutter/material.dart';
import '../models/number_item.dart';
import '../services/number_filter.dart';
import 'number_tile.dart';

/// 评论弹窗（底部弹出的 BottomSheet）：
/// - 顶部「刷新」按钮：重新抓取当前链接的评论
/// - 顶部「粘贴」按钮：手动粘贴文本兜底（抓不到网页时用）
/// - 列表：最多显示最近 5 个有效 9 位数字，每条带「复制」按钮
class CommentBottomSheet extends StatefulWidget {
  final List<NumberItem> initialNumbers;
  final String url;
  final String? error;
  final Future<List<NumberItem>> Function() onRefresh;

  const CommentBottomSheet({
    super.key,
    required this.initialNumbers,
    required this.url,
    this.error,
    required this.onRefresh,
  });

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet> {
  late List<NumberItem> _numbers;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _numbers = List.from(widget.initialNumbers);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final nums = await widget.onRefresh();
      setState(() => _numbers = nums);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新失败：$e')));
      }
    } finally {
      setState(() => _refreshing = false);
    }
  }

  // 粘贴兜底：把用户粘进来的整段文本按行拆成"评论"，再提取 9 位数字
  Future<void> _paste() async {
    final text = await _showPasteDialog();
    if (text == null || text.trim().isEmpty) return;
    final parts = text.split(RegExp(r'[\n\r]+'));
    final extracted = NumberFilter.extractFromComments(parts, max: 5);
    if (extracted.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('粘贴内容里没有有效的 9 位数字')));
      }
      return;
    }
    setState(() {
      for (final e in extracted) {
        if (!_numbers.any((n) => n.value == e.value)) {
          _numbers.insert(0, e);
        }
      }
      if (_numbers.length > 5) _numbers = _numbers.sublist(0, 5);
    });
  }

  Future<String?> _showPasteDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴评论文本'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '把评论或含数字的文字粘贴到这里',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('提取')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('最新数字',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    tooltip: '刷新',
                  ),
                  IconButton(
                    onPressed: _paste,
                    icon: const Icon(Icons.paste),
                    tooltip: '粘贴',
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('自动抓取失败，可点「粘贴」手动输入',
                  style: TextStyle(color: Colors.red[700])),
            ),
          if (_numbers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无符合条件的数字',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._numbers.map((n) => NumberTile(item: n)).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
