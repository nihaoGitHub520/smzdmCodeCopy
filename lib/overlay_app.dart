import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'models/comment_item.dart';
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
  List<CommentItem> _comments = [];
  bool _loading = false;
  String _status = '';

  /// 当前窗口尺寸（dp），用于「放大 / 缩小」按钮
  int _w = kOverlayDefaultWidth;
  int _h = kOverlayDefaultHeight;

  @override
  void initState() {
    super.initState();
    _listenMessages();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadLocalSettings();
    if (!mounted) return;
    await _refresh();
  }

  /// 读取上次保存的链接与窗口尺寸（读不到就保持默认值，不报错）
  Future<void> _loadLocalSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      final w = p.getInt(kPrefOverlayWidth);
      final h = p.getInt(kPrefOverlayHeight);
      final u = p.getString(kPrefUrl);
      if (!mounted) return;
      setState(() {
        if (w != null && w >= kOverlayMinWidth) _w = w;
        if (h != null && h >= kOverlayMinHeight) _h = h;
        if (u != null && u.trim().isNotEmpty) _url = u;
      });
    } catch (_) {
      // 悬浮窗引擎里没有存储插件时忽略，用默认值即可
    }
  }

  /// 接收主 App 的消息：url:链接 / size:宽,高 / refresh
  void _listenMessages() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is! String || event.isEmpty) return;
        if (event.startsWith('size:')) {
          final parts = event.substring(5).split(',');
          if (parts.length == 2) {
            final w = int.tryParse(parts[0].trim());
            final h = int.tryParse(parts[1].trim());
            if (w != null && h != null) {
              setState(() {
                _w = w;
                _h = h;
              });
            }
          }
        } else if (event.startsWith('url:')) {
          final u = event.substring(4).trim();
          if (u.isNotEmpty && u != _url) {
            _url = u;
            _refresh();
          }
        } else if (event == 'refresh') {
          _refresh();
        }
      });
    } catch (_) {}
  }

  /// 刷新：重新请求接口（内部会自动归一化链接）并重新解析
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = '抓取中…';
    });
    try {
      final comments = await SmzdmService.fetchComments(_url);
      if (!mounted) return;
      final show = comments.take(kMaxShowComments).toList();
      setState(() {
        _comments = show;
        _status = show.isEmpty
            ? '未获取到评论，点刷新重试'
            : '${show.length} 条最新评论 · 拖标题可移动 · 点 ⤢ 可调大小';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '抓取失败，点刷新重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 缩小 / 放大悬浮窗（步长 kOverlayStep），并同步给主 App 保存
  Future<void> _changeSize(int dw, int dh) async {
    final nw = (_w + dw).clamp(kOverlayMinWidth, 3000).toInt();
    final nh = (_h + dh).clamp(kOverlayMinHeight, 4000).toInt();
    setState(() {
      _w = nw;
      _h = nh;
      _status = '窗口尺寸 $nw × $nh';
    });
    try {
      await FlutterOverlayWindow.resizeOverlay(nw, nh, true);
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(kPrefOverlayWidth, nw);
      await p.setInt(kPrefOverlayHeight, nh);
    } catch (_) {}
    _broadcast('sizeChanged:$nw,$nh');
  }

  void _broadcast(String msg) {
    try {
      FlutterOverlayWindow.shareData(msg);
    } catch (_) {}
  }

  /// 复制：有 9 位码就复制码，否则复制整条评论
  Future<void> _copy(CommentItem item) async {
    final value = item.code ?? item.text;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      setState(() =>
          _status = item.code != null ? '已复制码 ${item.code}' : '已复制评论');
    }
  }

  /// 原生通道：由 PreloadApp 注册，直接 startActivity 拉起深链。
  /// 悬浮窗是独立 Flutter 引擎，url_launcher 不一定注册得上，这条最可靠。
  static const MethodChannel _nativeChannel = MethodChannel('smzdm/open_url');

  Future<bool> _nativeOpen(String url) async {
    try {
      final ok = await _nativeChannel.invokeMethod<bool>('open', {'url': url});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// 点「拼多多」：用该行的 9 位码直接打开拼多多搜索页
  Future<void> _openPdd(CommentItem item) async {
    final code = item.code;
    if (code == null) return;
    final deep = pddSearchUrl(code);

    // 1) 原生通道（悬浮窗里最可靠）
    if (await _nativeOpen(deep)) {
      if (mounted) setState(() => _status = '已在拼多多搜索 $code');
      return;
    }

    // 2) url_launcher 深链
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(deep),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (ok) {
      if (mounted) setState(() => _status = '已在拼多多搜索 $code');
      return;
    }

    // 3) 转给主 App 打开
    _broadcast('open:$deep');

    // 4) 最后退到 H5 搜索页
    try {
      ok = await launchUrl(
        Uri.parse(pddWebUrl(code)),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() => _status =
          ok ? '已打开拼多多搜索 $code' : '打开失败：请确认已安装拼多多');
    }
  }

  Future<void> _close() async {
    // 先把「已关闭」状态落盘，保证下次启动不会自动弹窗
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kPrefOverlayEnabled, false);
    } catch (_) {}
    _broadcast('closed:1');
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Material(
        elevation: 10,
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(),
            _loading
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox(height: 2),
            Expanded(child: _buildList()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.only(left: 9, right: 3, top: 3, bottom: 3),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, size: 15, color: Color(0xFFE65100)),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              '最新评论',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          _tinyBtn(Icons.zoom_out, '缩小窗口',
              () => _changeSize(-kOverlayStep, -kOverlayStep)),
          _tinyBtn(Icons.zoom_in, '放大窗口',
              () => _changeSize(kOverlayStep, kOverlayStep)),
          _tinyBtn(Icons.refresh, '刷新', _loading ? null : _refresh),
          _tinyBtn(Icons.close, '关闭悬浮窗', _close),
        ],
      ),
    );
  }

  Widget _tinyBtn(IconData icon, String tip, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Tooltip(
        message: tip,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon,
              size: 18,
              color: onTap == null ? Colors.black26 : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _loading ? '加载中…' : '暂无评论，点刷新重试',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const Divider(height: 9),
      itemBuilder: (_, i) {
        final c = _comments[i];
        return _CommentRow(
          item: c,
          onCopy: () => _copy(c),
          onOpenPdd: () => _openPdd(c),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(9, 3, 9, 5),
      child: Text(
        _status.isEmpty ? '就绪' : _status,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.black54),
      ),
    );
  }
}

/// 单条评论：正文 + 时间 + 码标签 + 复制 + 拼多多链接
class _CommentRow extends StatelessWidget {
  final CommentItem item;
  final VoidCallback onCopy;
  final VoidCallback onOpenPdd;

  const _CommentRow({
    required this.item,
    required this.onCopy,
    required this.onOpenPdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, height: 1.28),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 7,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 11, color: Colors.black38),
                const SizedBox(width: 2),
                Text(
                  item.time.isEmpty ? '—' : item.time,
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
              ],
            ),
            if (item.code != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0x26FF9800),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.code!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
            _MiniBtn(
              icon: Icons.copy,
              label: item.code != null ? '复制码' : '复制',
              color: const Color(0xFF1976D2),
              onTap: onCopy,
            ),
            if (item.code != null)
              _MiniBtn(
                icon: Icons.open_in_new,
                label: '拼多多',
                color: const Color(0xFFD32F2F),
                onTap: onOpenPdd,
              ),
          ],
        ),
      ],
    );
  }
}

/// 行内的小按钮（比 TextButton 省空间，窄窗口也不溢出）
class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
