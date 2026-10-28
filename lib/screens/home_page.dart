import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/comment_item.dart';
import '../services/smzdm_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  String _status = '就绪';
  bool _busy = false;
  List<CommentItem> _comments = [];

  // ---- 悬浮窗设置 ----
  bool _overlayEnabled = true; // 悬浮窗是否显示（用户可关）
  int _ow = kOverlayDefaultWidth;
  int _oh = kOverlayDefaultHeight;
  double _screenW = 0;
  double _screenH = 0;

  double get _sliderMaxW =>
      _screenW > kOverlayMinWidth + 60 ? _screenW : 480.0;

  double get _sliderMaxH =>
      _screenH > kOverlayMinHeight + 60 ? _screenH : 900.0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _readScreenSize();
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(kPrefUrl) ?? kDefaultUrl;
    final enabled = prefs.getBool(kPrefOverlayEnabled) ?? true;
    final w = prefs.getInt(kPrefOverlayWidth) ?? kOverlayDefaultWidth;
    final h = prefs.getInt(kPrefOverlayHeight) ?? kOverlayDefaultHeight;
    if (!mounted) return;
    _urlController.text = url;
    setState(() {
      _overlayEnabled = enabled;
      _ow = w;
      _oh = h;
    });
    _listenOverlayMessages();

    // 上次是开启状态，就自动恢复悬浮窗（已授权时不再弹系统页）
    if (enabled) {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (granted == true) {
        final ok = await _showOverlay();
        if (mounted) {
          setState(() => _status = ok ? '已恢复悬浮窗显示' : '恢复悬浮窗失败，可手动开启');
        }
      }
    }
  }

  Future<void> _readScreenSize() async {
    try {
      final s = await FlutterOverlayWindow.getScreenSize();
      // 注意：flutter_overlay_window 把屏幕「宽/高」放在 OverlayPosition 的 x/y 里
      final w = s.x;
      final h = s.y;
      if (w > 0 && h > 0 && mounted) {
        setState(() {
          _screenW = w;
          _screenH = h;
        });
      }
    } catch (_) {}
  }

  /// 接收悬浮窗发来的消息：尺寸变化 / 关闭 / 请求打开链接
  void _listenOverlayMessages() {
    try {
      FlutterOverlayWindow.overlayListener.listen((event) async {
        if (event is! String || event.isEmpty) return;
        if (event.startsWith('sizeChanged:')) {
          final p = event.substring(11).split(',');
          if (p.length == 2) {
            final w = int.tryParse(p[0].trim());
            final h = int.tryParse(p[1].trim());
            if (w != null && h != null) {
              if (mounted) {
                setState(() {
                  _ow = w;
                  _oh = h;
                });
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(kPrefOverlayWidth, w);
              await prefs.setInt(kPrefOverlayHeight, h);
            }
          }
        } else if (event.startsWith('closed:')) {
          if (mounted) {
            setState(() {
              _overlayEnabled = false;
              _status = '悬浮窗已关闭';
            });
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(kPrefOverlayEnabled, false);
        } else if (event.startsWith('open:')) {
          await _openUrl(event.substring(5));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefUrl, url);
  }

  Future<void> _saveEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefOverlayEnabled, v);
  }

  Future<void> _saveSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefOverlayWidth, _ow);
    await prefs.setInt(kPrefOverlayHeight, _oh);
  }

  /// 抓取最新评论，并把归一化后的链接回填到输入框
  Future<List<CommentItem>> _fetch() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) throw Exception('请先填写链接');
    final norm = SmzdmService.normalizeUrl(raw);
    final comments = await SmzdmService.fetchComments(norm);
    if (mounted) _urlController.text = norm;
    await _saveUrl(norm);
    return comments;
  }

  /// 主界面预览（不开悬浮窗也能看）
  Future<void> _refreshPreview() async {
    setState(() => _busy = true);
    try {
      final comments = await _fetch();
      if (!mounted) return;
      setState(() {
        _comments = comments.take(kMaxShowComments).toList();
        _status = comments.isEmpty
            ? '内容里没解析到评论'
            : '已获取 ${comments.length} 条最新评论';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '抓取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 显示系统悬浮窗（会自动申请「显示在其他应用上层」权限）
  Future<bool> _showOverlay() async {
    var granted = (await FlutterOverlayWindow.isPermissionGranted()) == true;
    if (!granted) {
      granted = (await FlutterOverlayWindow.requestPermission()) == true;
    }
    if (!granted) {
      if (mounted) {
        setState(() => _status = '未授予「显示在其他应用上层」权限，无法显示悬浮窗');
      }
      return false;
    }

    final url = SmzdmService.normalizeUrl(_urlController.text.trim().isEmpty
        ? kDefaultUrl
        : _urlController.text.trim());
    if (mounted) _urlController.text = url;
    await _saveUrl(url);

    await FlutterOverlayWindow.showOverlay(
      height: _oh,
      width: _ow,
      alignment: OverlayAlignment.center,
      enableDrag: true,
      dismissConfig: const OverlayDismissConfig(),
      overlayTitle: '最新评论悬浮窗',
      overlayContent: '点刷新可重新请求最新评论，可复制码或直接搜拼多多',
    );

    _broadcast('url:$url');
    _broadcast('size:$_ow,$_oh');
    return true;
  }

  void _broadcast(String msg) {
    try {
      FlutterOverlayWindow.shareData(msg);
    } catch (_) {}
  }

  /// 开关：显示 / 隐藏悬浮窗（并持久化，下次启动按此状态）
  Future<void> _setOverlayEnabled(bool v) async {
    if (v) {
      setState(() => _busy = true);
      final ok = await _showOverlay();
      await _saveEnabled(ok);
      if (mounted) {
        setState(() {
          _overlayEnabled = ok;
          _busy = false;
          if (ok) _status = '悬浮窗已开启，可退回桌面，窗口会一直显示';
        });
      }
    } else {
      try {
        await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
      await _saveEnabled(false);
      if (mounted) {
        setState(() {
          _overlayEnabled = false;
          _status = '悬浮窗已关闭';
        });
      }
    }
  }

  /// 尺寸改变后应用到已显示的悬浮窗并保存
  Future<void> _applySize() async {
    await _saveSize();
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (active) {
        await FlutterOverlayWindow.resizeOverlay(_ow, _oh, true);
      }
    } catch (_) {}
    _broadcast('size:$_ow,$_oh');
  }

  Future<void> _copy(CommentItem item) async {
    final value = item.code ?? item.text;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      setState(() =>
          _status = item.code != null ? '已复制码 ${item.code}' : '已复制评论');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 用该行的 9 位码打开拼多多搜索（深链失败则退到 H5）
  Future<void> _openPdd(CommentItem item) async {
    final code = item.code;
    if (code == null) return;
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(pddSearchUrl(code)),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      try {
        ok = await launchUrl(
          Uri.parse(pddWebUrl(code)),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        ok = false;
      }
    }
    if (mounted) {
      setState(() => _status =
          ok ? '已打开拼多多搜索 $code' : '打开失败：请确认已安装拼多多');
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('评论悬浮窗'),
        actions: [
          IconButton(
            tooltip: '刷新预览',
            onPressed: _busy ? null : _refreshPreview,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('监控链接（可粘贴任意 smzdm 链接，会自动提取页面ID）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '粘贴什么值得买链接，或直接填页面ID',
              isDense: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _refreshPreview,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(_busy ? '处理中…' : '抓取最新评论'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---------------- 悬浮窗设置 ----------------
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  value: _overlayEnabled,
                  onChanged: (v) => _setOverlayEnabled(v),
                  secondary: const Icon(Icons.picture_in_picture_alt),
                  title: const Text('显示悬浮窗',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    _overlayEnabled ? '已开启：在其他应用上层常驻显示' : '已关闭：不显示悬浮窗',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('悬浮窗大小',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('$_ow × $_oh',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                      _sizeRow(
                        label: '宽',
                        value: _ow,
                        min: kOverlayMinWidth.toDouble(),
                        max: _sliderMaxW,
                        onChanged: (v) => setState(() => _ow = v.round()),
                      ),
                      _sizeRow(
                        label: '高',
                        value: _oh,
                        min: kOverlayMinHeight.toDouble(),
                        max: _sliderMaxH,
                        onChanged: (v) => setState(() => _oh = v.round()),
                      ),
                      if (_screenW > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '屏幕约 ${_screenW.round()} × ${_screenH.round()} dp'
                            '（建议高度不超过 ${(_screenH * 0.8).round()}）',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('状态：$_status',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Divider(height: 22),

          if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Text(
                '点「抓取最新评论」可在此预览；\n'
                '开启「显示悬浮窗」后，窗口会显示在其他应用上层。',
                style: TextStyle(color: Colors.grey, height: 1.6, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._comments.map(_buildPreviewTile),
        ],
      ),
    );
  }

  Widget _sizeRow({
    required String label,
    required int value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final v = value.toDouble().clamp(min, max).toDouble();
    return Row(
      children: [
        SizedBox(
            width: 20,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: v,
            divisions: ((max - min) / 10).round().clamp(1, 100).toInt(),
            label: '${v.round()}',
            onChanged: onChanged,
            onChangeEnd: (_) => _applySize(),
          ),
        ),
        SizedBox(
          width: 46,
          child: Text('${v.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      ],
    );
  }

  Widget _buildPreviewTile(CommentItem c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 12, color: Colors.black38),
                  const SizedBox(width: 2),
                  Text(c.time.isEmpty ? '—' : c.time,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ],
              ),
              if (c.code != null)
                Text(c.code!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100))),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _copy(c),
                icon: const Icon(Icons.copy, size: 14),
                label: Text(c.code != null ? '复制码' : '复制',
                    style: const TextStyle(fontSize: 12)),
              ),
              if (c.code != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFFD32F2F),
                  ),
                  onPressed: () => _openPdd(c),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('拼多多搜',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
