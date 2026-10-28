import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/comment_item.dart';
import '../models/discover_item.dart';
import 'number_filter.dart';

/// 抓「什么值得买」的数据：
/// 1) 发现页的最新爆料列表 → 取第一条的页面 ID
/// 2) 用页面 ID 抓该页面「最新评论」
///
/// 关键点（2026-10 实测）：
/// - 评论是 **服务端直出** 在 HTML 里的，不需要评论接口，禁用 F12 也不影响。
/// - 页面里同时有「热门」`#commentTabBlockHot` 和「最新」`#commentTabBlockNew`，
///   我们要的是「最新」，所以限定在 `#commentTabBlockNew` 内取。
/// - 每条评论正文：`.comment-main-list-item-content-comment`
/// - 评论时间：`.comment-main-list-item-content-info .content-info span`
/// - 发现页列表：`#feed-main-list` 下的 `<li>`，条目自带 `articleid="3_184902762"`
///   和 `href="https://www.smzdm.com/p/184902762/"`，取第一个即可。
class SmzdmService {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // -------------------------------------------------------------------------
  // 链接处理
  // -------------------------------------------------------------------------

  /// 由页面 ID 生成标准「最新评论」地址
  static String commentsUrl(String articleId) =>
      'https://www.smzdm.com/p/$articleId/p1/?sort_tab=new/';

  /// 把用户粘贴的任意 smzdm 链接归一化成标准「最新评论」地址
  ///
  /// 支持：
  /// - https://www.smzdm.com/p/184881376/  (任意 query)
  /// - https://www.smzdm.com/p/184881376/p1/?sort_tab=new/#comments
  /// - 只贴了页面 ID：184881376
  static String normalizeUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;

    // 1) 优先从路径 /p/<数字> 提取页面 ID
    var m = RegExp(r'/p/(\d+)').firstMatch(raw);
    // 2) 退而求其次：找孤立的 9 位数字（用户可能只贴了 ID）
    m ??= RegExp(r'(?:^|[^0-9])([0-9]{9})(?:[^0-9]|$)').firstMatch(raw);

    final id = m?.group(1);
    if (id != null && id.isNotEmpty) return commentsUrl(id);

    // 3) 实在找不到 ID，就原样使用（去掉锚点）
    return raw.split('#').first;
  }

  // -------------------------------------------------------------------------
  // 发现页：最新爆料
  // -------------------------------------------------------------------------

  /// 抓发现页，按页面顺序返回爆料列表（最多 [limit] 条）
  static Future<List<DiscoverItem>> fetchDiscoverItems(
    String discoverUrl, {
    int limit = 10,
  }) async {
    final raw = discoverUrl.trim().isEmpty ? _defaultDiscover : discoverUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null) throw Exception('发现页链接格式不正确');

    final body = await _get(uri.replace(fragment: ''), raw);
    return parseDiscoverItems(body, limit: limit);
  }

  static const _defaultDiscover =
      'https://faxian.smzdm.com/h2s8645t0f0c0p1/';

  /// 从发现页 HTML 里解析爆料列表（纯净函数，方便单测）
  static List<DiscoverItem> parseDiscoverItems(String html, {int limit = 10}) {
    final doc = html_parser.parse(html);
    final container = doc.querySelector('#feed-main-list');
    if (container == null) {
      throw Exception('发现页里没找到爆料列表（#feed-main-list）');
    }

    final items = <DiscoverItem>[];
    for (final li in container.querySelectorAll('li')) {
      final id = _articleIdOf(li);
      if (id == null) continue;

      items.add(DiscoverItem(
        id: id,
        title: _plainText(li.querySelector('.feed-ver-title')),
        mall: _plainText(li.querySelector('a.tag-bottom-right')),
        price: _plainText(li.querySelector('.z-highlight')),
        time: _plainText(li.querySelector('.feed-ver-date')),
      ));
      if (items.length >= limit) break;
    }

    if (items.isEmpty) throw Exception('爆料列表里没有可用的页面ID');
    return items;
  }

  /// 取一个 `<li>` 的页面 ID：先看 articleid 属性，再退回 /p/<id>/ 链接
  static String? _articleIdOf(Element li) {
    final attr = li.attributes['articleid'];
    if (attr != null) {
      final m = RegExp(r'(\d{6,})').firstMatch(attr);
      if (m != null) return m.group(1);
    }
    final href = li.querySelector('a[href*="/p/"]')?.attributes['href'];
    if (href != null) {
      final m = RegExp(r'/p/(\d+)').firstMatch(href);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String _plainText(Element? el) =>
      (el?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // -------------------------------------------------------------------------
  // 详情页：最新评论
  // -------------------------------------------------------------------------

  /// 用页面 ID 抓「最新评论」
  static Future<List<CommentItem>> fetchCommentsByArticleId(String id) =>
      fetchComments(commentsUrl(id));

  /// 抓取并解析「最新评论」，返回评论列表（正文 + 时间 + 9 位数字）
  static Future<List<CommentItem>> fetchComments(String url) async {
    final target = normalizeUrl(url);
    final uri = Uri.tryParse(target);
    if (uri == null) throw Exception('链接格式不正确');

    final body = await _get(uri.replace(fragment: ''), target);
    return parseComments(body);
  }

  /// 从详情页 HTML 解析最新评论（纯净函数，方便单测）
  static List<CommentItem> parseComments(String html) {
    final doc = html_parser.parse(html);

    // 限定「最新」列表；若页面结构变化则退回全局
    var items =
        doc.querySelectorAll('#commentTabBlockNew li.comment-main-list-item');
    if (items.isEmpty) {
      items = doc.querySelectorAll('li.comment-main-list-item');
    }

    if (items.isEmpty) {
      // 再兜底：直接找正文节点
      final fallback = <CommentItem>[];
      for (final b
          in doc.querySelectorAll('.comment-main-list-item-content-comment')) {
        final t = _plainText(b);
        if (t.isNotEmpty) {
          fallback.add(CommentItem(
            text: t,
            time: '',
            code: NumberFilter.collapseTo9(t),
          ));
        }
      }
      return fallback;
    }

    final list = <CommentItem>[];
    for (final li in items) {
      final text =
          _plainText(li.querySelector('.comment-main-list-item-content-comment'));
      if (text.isEmpty) continue;

      final time = _plainText(li
          .querySelector('.comment-main-list-item-content-info .content-info span'));

      list.add(CommentItem(
        text: text,
        time: time,
        code: NumberFilter.collapseTo9(text),
      ));
    }
    return list;
  }

  // -------------------------------------------------------------------------
  // 通用 GET
  // -------------------------------------------------------------------------

  static Future<String> _get(Uri uri, String referer) async {
    final resp = await http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': referer,
      },
    ).timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      throw Exception('网页返回状态码 ${resp.statusCode}');
    }
    // 统一按 UTF-8 解码，避免中文乱码
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }
}
