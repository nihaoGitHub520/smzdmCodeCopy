import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/number_item.dart';
import '../services/number_filter.dart';
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
  List<NumberItem> _preview = [];

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

  /// 启动系统悬浮窗（显示在其他应用上层，可后台常驻）
  Future<void> _startOverlay() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '请先填写链接');
      return;
    }
    setState(() => _busy = true);
    try {
      await _saveUrl(url);

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
        height: 340,
        width: 312,
        alignment: OverlayAlignment.center,
        enableDrag: true,
        dismissConfig: const OverlayDismissConfig(),
        overlayTitle: '评论数字悬浮窗',
        overlayContent: '后台监控中，点悬浮窗可刷新/粘贴/复制',
      );

      // 3) 把当前链接同步给悬浮窗（best-effort）
      try {
        await FlutterOverlayWindow.shareData(url);
      } catch (_) {}

      setState(() => _status = '悬浮窗已启动，可退回桌面，窗口会一直显示');

      // 4) 主界面顺带抓一次，做个小预览
      try {
        final comments = await SmzdmService.fetchComments(url);
        final nums = NumberFilter.extractFromComments(comments, max: 5);
        if (mounted) {
          setState(() {
            _preview = nums;
            _status = '抓到 ${comments.length} 条评论，有效数字 ${nums.length} 个';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _status = '悬浮窗已启动（自动抓取失败，可在悬浮窗里点「粘贴」）');
        }
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('评论数字悬浮窗')),
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
                    label: Text(_busy ? '启动中…' : '启动悬浮窗'),
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
            const SizedBox(height: 16),
            Text('状态：$_status',
                style: const TextStyle(color: Colors.grey)),
            const Divider(height: 32),
            if (_preview.isNotEmpty) ...[
              const Text('最近有效数字',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._preview.map((n) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.tag),
                    title: Text(n.value,
                        style: const TextStyle(
                            fontSize: 18, letterSpacing: 1)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        // 主界面本身也能复制（悬浮窗里也能复制）
                      },
                    ),
                  )),
            ] else
              const Text(
                '点「启动悬浮窗」后，悬浮窗会显示在其他应用上层；\n'
                '窗口里可刷新、可粘贴剪贴板文本提取、可一键复制。',
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
          ],
        ),
      ),
    );
  }
}
