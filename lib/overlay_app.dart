import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'constants.dart';
import 'models/comment_item.dart';
import 'services/smzdm_service.dart';

/// 悬浮窗里最多显示多少条最新评论
const int _kMaxShow = 5;

/// 悬浮窗应用根（由 overlayMain 启动，运行在独立的 Flutter 引擎里）。
class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.orange),
      home: const OverlayPage(),
    );
  }
}

class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key});

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  /// 当前监控的链接（主 App 可通过 shareData 替换）
  String _url = kDefaultUrl;
  List<CommentItem> _comments = [];
  bool _loading = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _listenForUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// 接收主 App 通过 shareData 传来的链接（best-effort，失败用默认链接）
  void _listenForUrl() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is String && event.trim().isNotEmpty && event != _url) {
          _url = event;
          _refresh();
        }
      });
    } catch (_) {}
  }

  /// 刷新：重新请求接口（内部会自动归一化链接）并处理
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = '抓取中…';
    });
    try {
      final comments = await SmzdmService.fetchComments(_url);
      if (!mounted) return;
      final show = comments.take(_kMaxShow).toList();
      setState(() {
        _comments = show;
        _status = show.isEmpty
            ? '未获取到评论'
            : '共 ${comments.length} 条，显示最近 ${show.length} 条';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '抓取失败，请点刷新重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 复制：有 9 位数字就复制数字，否则复制整条评论
  Future<void> _copy(CommentItem item) async {
    final value = item.code ?? item.text;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      setState(() => _status =
          item.code != null ? '已复制码 ${item.code}' : '已复制评论');
    }
  }

  Future<void> _close() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          child: Container(
            width: 336,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部栏：标题 + 刷新 + 关闭
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '最新评论',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '刷新',
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh, size: 22),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '关闭悬浮窗',
                      onPressed: _close,
                      icon: const Icon(Icons.close, size: 22),
                    ),
                  ],
                ),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                const Divider(height: 8),

                // 评论列表（每条：正文 + 时间 + 复制按钮）
                if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Text('暂无评论',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._comments.map((c) => _CommentRow(
                        item: c,
                        onCopy: () => _copy(c),
                      )),

                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _status,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final CommentItem item;
  final VoidCallback onCopy;

  const _CommentRow({required this.item, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 评论正文
          Text(
            item.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 3),
          // 时间 + 数字标签 + 复制
          Row(
            children: [
              const Icon(Icons.schedule, size: 12, color: Colors.black45),
              const SizedBox(width: 3),
              Text(
                item.time.isEmpty ? '—' : item.time,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(width: 8),
              if (item.code != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x26FF9800),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.code!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 15),
                  label: Text(
                    item.code != null ? '复制码' : '复制',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
