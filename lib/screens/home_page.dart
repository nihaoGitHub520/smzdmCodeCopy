import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/comment_item.dart';
import '../models/discover_item.dart';
import '../services/number_filter.dart';
import '../services/smzdm_service.dart';

/// 列表来源：自动（发现页第一条爆料） / 手动（输入框里的链接）
enum FetchMode { auto, manual }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  final _discoverController = TextEditingController();

  String _status = '正在启动…';
  bool _busy = false;
  List<CommentItem> _comments = [];
  List<DiscoverItem> _feeds = [];
  int _feedIndex = 0;
  FetchMode _mode = FetchMode.auto;
  bool _settingsOpen = false;

  DiscoverItem? get _feed =>
      (_feedIndex >= 0 && _feedIndex < _feeds.length) ? _feeds[_feedIndex] : null;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _discoverController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // 启动 / 持久化
  // -------------------------------------------------------------------------

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(kPrefUrl) ?? kDefaultUrl;
    final discover = prefs.getString(kPrefDiscoverUrl) ?? kDiscoverUrl;
    if (!mounted) return;
    _urlController.text = url;
    _discoverController.text = discover;
    // 打开 App 就自动去拿最新爆料的第一条
    await _autoFetch();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefDiscoverUrl, _discoverController.text.trim());
    final url = _urlController.text.trim();
    if (url.isNotEmpty) await prefs.setString(kPrefUrl, url);
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  // -------------------------------------------------------------------------
  // 自动：发现页第一条爆料 → 它的最新评论
  // -------------------------------------------------------------------------

  Future<void> _autoFetch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _mode = FetchMode.auto;
      _status = '正在打开发现页，找最新爆料…';
    });
    try {
      final feeds = await SmzdmService.fetchDiscoverItems(
        _discoverController.text,
        limit: kDiscoverFeedLimit,
      );
      if (!mounted) return;
      setState(() {
        _feeds = feeds;
        _feedIndex = 0;
      });
      await _loadComments(feeds.first);
      await _persist();
    } catch (e) {
      _setStatus('自动获取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 读取某条爆料的最新评论
  Future<void> _loadComments(DiscoverItem item) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _comments = [];
        _status = '正在读取 ${item.id} 的最新评论…';
      });
    }
    final url = SmzdmService.commentsUrl(item.id);
    if (mounted) _urlController.text = url;

    final comments = await SmzdmService.fetchCommentsByArticleId(item.id);
    if (!mounted) return;
    setState(() {
      _comments = comments.take(kMaxShowComments).toList();
      _status = comments.isEmpty
          ? '这条爆料还没有最新评论，可点「下一条」'
          : '${comments.length} 条最新评论';
      _busy = false;
    });
  }

  /// 第一个爆料没评论时，往后翻一条
  Future<void> _nextFeed() async {
    if (_busy) return;
    if (_feedIndex + 1 >= _feeds.length) {
      _setStatus('已经是最后一条了，点右上角刷新重新拉取');
      return;
    }
    setState(() => _feedIndex++);
    try {
      await _loadComments(_feeds[_feedIndex]);
    } catch (e) {
      _setStatus('读取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // 手动：用输入框里的链接
  // -------------------------------------------------------------------------

  Future<void> _fetchManual() async {
    if (_busy) return;
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      _setStatus('请先填写链接或页面ID');
      return;
    }
    setState(() {
      _busy = true;
      _mode = FetchMode.manual;
      _status = '正在读取评论…';
    });
    try {
      final norm = SmzdmService.normalizeUrl(raw);
      if (mounted) _urlController.text = norm;
      final comments = await SmzdmService.fetchComments(norm);
      if (!mounted) return;
      setState(() {
        _comments = comments.take(kMaxShowComments).toList();
        _status = comments.isEmpty ? '没解析到评论' : '${comments.length} 条最新评论';
      });
      await _persist();
    } catch (e) {
      _setStatus('抓取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 右上角刷新：按上次的来源刷新
  Future<void> _refresh() =>
      _mode == FetchMode.auto ? _autoFetch() : _fetchManual();

  // -------------------------------------------------------------------------
  // 复制 / 跳拼多多 / 粘贴兜底
  // -------------------------------------------------------------------------

  Future<void> _copy(CommentItem item) async {
    final value = item.code ?? item.text;
    await Clipboard.setData(ClipboardData(text: value));
    _setStatus(item.code != null ? '已复制码 ${item.code}' : '已复制评论');
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
    _setStatus(ok ? '已打开拼多多搜索 $code' : '打开失败：请确认已安装拼多多');
  }

  /// 兜底：从剪贴板提取 9 位码（网页抓不到时用）
  Future<void> _pasteExtract() async {
    var text = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text ?? '';
    } catch (_) {
      text = '';
    }
    if (text.trim().isEmpty) {
      _setStatus('剪贴板是空的');
      return;
    }

    final found = <CommentItem>[];
    for (final line in text.split(RegExp(r'[\n\r]+'))) {
      final t = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) continue;
      final code = NumberFilter.collapseTo9(t);
      if (code == null) continue;
      if (_comments.any((c) => c.code == code)) continue;
      if (found.any((c) => c.code == code)) continue;
      found.add(CommentItem(text: t, time: '来自粘贴', code: code));
    }

    if (found.isEmpty) {
      _setStatus('粘贴的内容里没有 9 位数字');
      return;
    }
    setState(() {
      _comments = [...found, ..._comments];
      if (_comments.length > kMaxShowComments) {
        _comments = _comments.sublist(0, kMaxShowComments);
      }
      _status = '从剪贴板提取到 ${found.length} 个码';
    });
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            _buildFeedCard(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _autoFetch,
                    icon: const Icon(Icons.bolt, size: 18),
                    label: Text(_busy ? '处理中…' : '自动取最新爆料'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _nextFeed,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('下一条'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ------- 当前监控链接 -------
            const Text('当前监控链接（点「抓取此链接」可手动指定）',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            const SizedBox(height: 6),
            TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: '粘贴什么值得买链接，或直接填页面ID',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _fetchManual,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('抓取此链接'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pasteExtract,
                  icon: const Icon(Icons.paste, size: 18),
                  label: const Text('粘贴提取'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('状态：$_status',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),

            // ------- 更多设置（发现页链接） -------
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                initiallyExpanded: _settingsOpen,
                onExpansionChanged: (v) => _settingsOpen = v,
                title: const Text('更多设置',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('发现页链接（自动取爆料就从这个页面取）',
                    style: TextStyle(fontSize: 11)),
                children: [
                  TextField(
                    controller: _discoverController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: '发现页链接',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '默认用「什么值得买发现页」，取列表里第一个爆料的页面ID。'
                    '如果以后这个链接失效，把新的发现页链接填到这里即可。',
                    style: TextStyle(fontSize: 11, color: Colors.black45, height: 1.4),
                  ),
                ],
              ),
            ),

            const Divider(height: 18),

            if (_comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  _busy
                      ? '正在获取…'
                      : '点「自动取最新爆料」自动抓第一条爆料的评论；\n'
                          '也可以粘贴任意商品链接再点「抓取此链接」。',
                  style: const TextStyle(
                      color: Colors.grey, height: 1.6, fontSize: 12.5),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._comments.map(_buildCommentTile),
          ],
        ),
      ),
    );
  }

  /// 顶部当前爆料卡片
  Widget _buildFeedCard() {
    final f = _feed;
    final title = f?.title ?? '';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    size: 16, color: Color(0xFFE65100)),
                const SizedBox(width: 4),
                Text(
                  f == null ? '最新爆料' : '第 ${_feedIndex + 1} 条爆料',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE65100)),
                ),
                const Spacer(),
                if (f != null)
                  Text('ID ${f.id}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title.isEmpty ? '尚未获取到爆料' : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            if (f != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (f.mall.isNotEmpty)
                    _chip(f.mall, const Color(0xFFD32F2F)),
                  if (f.price.isNotEmpty)
                    Text(f.price,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD32F2F))),
                  if (f.time.isNotEmpty)
                    Text(f.time,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, 0.88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  /// 单条评论：正文 / 时间 / 9位码 / 复制 / 拼多多
  Widget _buildCommentTile(CommentItem c) {
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
                  label:
                      const Text('拼多多搜', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
