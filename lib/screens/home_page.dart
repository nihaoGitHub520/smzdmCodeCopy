import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/comment_item.dart';
import '../services/smzdm_service.dart';

const String _kPrefUrl = 'monitor_url';

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

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString(_kPrefUrl) ?? kDefaultUrl;
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefUrl, url);
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

  /// 主界面预览（不弹悬浮窗）
  Future<void> _refreshPreview() async {
    setState(() => _busy = true);
    try {
      final comments = await _fetch();
      if (!mounted) return;
      setState(() {
        _comments = comments;
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

  /// 启动系统悬浮窗（显示在其他应用上层，可后台常驻）
  Future<void> _startOverlay() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _status = '请先填写链接');
      return;
    }
    setState(() => _busy = true);
    try {
      final norm = SmzdmService.normalizeUrl(raw);
      if (mounted) _urlController.text = norm;
      await _saveUrl(norm);

      // 1) 悬浮窗权限（SYSTEM_ALERT_WINDOW）
      var granted =
          (await FlutterOverlayWindow.isPermissionGranted()) == true;
      if (!granted) {
        granted = (await FlutterOverlayWindow.requestPermission()) == true;
      }
      if (!granted) {
        setState(() => _status = '未授予「显示在其他应用上层」权限，无法显示悬浮窗');
        return;
      }

      // 2) 显示悬浮窗
      await FlutterOverlayWindow.showOverlay(
        height: 500,
        width: 340,
        alignment: OverlayAlignment.center,
        enableDrag: true,
        dismissConfig: const OverlayDismissConfig(),
        overlayTitle: '最新评论悬浮窗',
        overlayContent: '点刷新可重新请求最新评论并复制',
      );

      // 3) 把链接同步给悬浮窗
      try {
        await FlutterOverlayWindow.shareData(norm);
      } catch (_) {}

      setState(() => _status = '悬浮窗已启动，可退回桌面，窗口会一直显示');

      // 4) 主界面顺带抓一次做预览
      try {
        final comments = await SmzdmService.fetchComments(norm);
        if (mounted) {
          setState(() {
            _comments = comments;
            _status = '悬浮窗已启动，已获取 ${comments.length} 条最新评论';
          });
        }
      } catch (_) {
        if (mounted) setState(() => _status = '悬浮窗已启动（主界面预览抓取失败，可在悬浮窗点刷新）');
      }
    } catch (e) {
      if (mounted) setState(() => _status = '启动失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
      if (mounted) setState(() => _status = '悬浮窗已关闭');
    } catch (e) {
      if (mounted) setState(() => _status = '关闭失败：$e');
    }
  }

  Future<void> _copy(CommentItem item) async {
    final value = item.code ?? item.text;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      setState(() => _status =
          item.code != null ? '已复制码 ${item.code}' : '已复制评论');
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('监控链接（可粘贴任意 smzdm 链接，会自动提取页面ID）',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '粘贴什么值得买链接，或直接填页面ID',
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _startOverlay,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_in_picture_alt),
                    label: Text(_busy ? '处理中…' : '启动悬浮窗'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _stopOverlay,
                  icon: const Icon(Icons.close),
                  label: const Text('关闭'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('状态：$_status',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(height: 20),
            Expanded(
              child: _comments.isEmpty
                  ? const Center(
                      child: Text(
                        '点「启动悬浮窗」后，悬浮窗会显示在其他应用上层；\n'
                        '也可点右上角刷新在此预览最新评论。',
                        style: TextStyle(color: Colors.grey, height: 1.6),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = _comments[i];
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(c.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Row(
                            children: [
                              Text(c.time,
                                  style: const TextStyle(fontSize: 11)),
                              if (c.code != null) ...[
                                const SizedBox(width: 8),
                                Text(c.code!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFE65100))),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: c.code != null ? '复制码' : '复制评论',
                            onPressed: () => _copy(c),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
