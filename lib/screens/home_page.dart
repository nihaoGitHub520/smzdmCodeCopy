import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/number_item.dart';
import '../services/smzdm_service.dart';
import '../services/number_filter.dart';
import '../widgets/comment_bottom_sheet.dart';

// 你给的默认监控链接（App 内可改成别的商品详情页）
const String _kDefaultUrl =
    'https://www.smzdm.com/p/184881376/?zdm_ss=Android_7827879137_&send_by=7827879137&from=other&invite_code=zdmam4wdehinv';
const String _kPrefUrl = 'monitor_url';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  String _status = '尚未抓取';
  bool _loading = false;
  List<NumberItem> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  // 启动时读取上次保存的链接（本地存储，无需登录）
  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString(_kPrefUrl) ?? _kDefaultUrl;
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefUrl, url);
  }

  // 点「打开评论弹窗」：先抓取 -> 过滤 -> 弹窗展示
  Future<void> _fetchAndShow() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '请先填写链接');
      return;
    }
    await _saveUrl(url);
    setState(() => _loading = true);
    try {
      final comments = await SmzdmService.fetchComments(url);
      final numbers = NumberFilter.extractFromComments(comments, max: 5);
      setState(() {
        _recent = numbers;
        _status = '抓到 ${comments.length} 条评论，有效 9 位数字 ${numbers.length} 个';
      });
      if (!mounted) return;
      _openSheet(numbers, url);
    } catch (e) {
      setState(() => _status = '抓取失败，可点弹窗里的「粘贴」手动输入');
      if (!mounted) return;
      _openSheet([], url, error: e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openSheet(List<NumberItem> numbers, String url, {String? error}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentBottomSheet(
        initialNumbers: numbers,
        url: url,
        error: error,
        onRefresh: () async {
          final comments = await SmzdmService.fetchComments(url);
          return NumberFilter.extractFromComments(comments, max: 5);
        },
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('评论数字提取器')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('监控链接（可修改）',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '粘贴什么值得买商品详情页链接',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _fetchAndShow,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.open_in_new),
                label: Text(_loading ? '抓取中…' : '打开评论弹窗'),
              ),
            ),
            const SizedBox(height: 16),
            Text('状态：$_status',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
