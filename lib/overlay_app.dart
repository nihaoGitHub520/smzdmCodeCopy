import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'constants.dart';
import 'models/number_item.dart';
import 'services/number_filter.dart';
import 'services/smzdm_service.dart';

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
  String _url = kDefaultUrl;
  List<NumberItem> _numbers = [];
  bool _loading = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _listenForUrl();
    _refresh();
  }

  /// 接收主 App 通过 shareData 传过来的链接（best-effort，失败不影响默认链接）
  void _listenForUrl() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is String &&
            event.startsWith('http') &&
            event != _url) {
          _url = event;
          _refresh();
        }
      });
    } catch (_) {
      // 悬浮窗引擎里若未注册该通道，忽略即可，用默认链接
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = '抓取中…';
    });
    try {
      final comments = await SmzdmService.fetchComments(_url);
      final nums = NumberFilter.extractFromComments(comments, max: 5);
      if (!mounted) return;
      setState(() {
        _numbers = nums;
        _status = nums.isEmpty
            ? '共 ${comments.length} 条评论，暂无 9 位数字'
            : '已更新（${comments.length} 条评论）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '抓取失败，可点「粘贴」手动提取');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 读取系统剪贴板，把里面的 9 位数字提取出来（无需弹键盘输入）
  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = (data?.text ?? '').trim();
      if (text.isEmpty) {
        setState(() => _status = '剪贴板为空');
        return;
      }
      final parts = text.split(RegExp(r'[\n\r]+'));
      final extracted = NumberFilter.extractFromComments(parts, max: 5);
      if (extracted.isEmpty) {
        final one = NumberFilter.collapseTo9(text);
        if (one == null) {
          setState(() => _status = '剪贴板里没有 9 位数字');
          return;
        }
        setState(() {
          _merge([NumberItem(value: one, source: text)]);
          _status = '已从剪贴板提取 1 个';
        });
        return;
      }
      setState(() {
        _merge(extracted);
        _status = '已从剪贴板提取 ${extracted.length} 个';
      });
    } catch (e) {
      setState(() => _status = '读取剪贴板失败');
    }
  }

  void _merge(List<NumberItem> items) {
    for (final e in items) {
      if (!_numbers.any((n) => n.value == e.value)) {
        _numbers.insert(0, e);
      }
    }
    if (_numbers.length > 5) {
      _numbers = _numbers.sublist(0, 5);
    }
  }

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (mounted) setState(() => _status = '已复制 $v');
  }

  Future<void> _close() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {
      // 若通道不可用，用户仍可通过「拖到底部关闭区」关闭悬浮窗
    }
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
            width: 300,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '最新9位数字',
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
                      tooltip: '粘贴剪贴板提取',
                      onPressed: _paste,
                      icon: const Icon(Icons.paste, size: 22),
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
                const Divider(height: 10),
                if (_numbers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('暂无符合条件的数字',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._numbers.map(
                    (n) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.value,
                            style: const TextStyle(
                              fontSize: 19,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '复制',
                          onPressed: () => _copy(n.value),
                          icon: const Icon(Icons.copy, size: 20),
                        ),
                      ],
                    ),
                  ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
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
