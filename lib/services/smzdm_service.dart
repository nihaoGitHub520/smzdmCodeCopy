import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

import '../models/comment_item.dart';
import 'number_filter.dart';

/// 抓取「什么值得买」详情页的 **最新评论**。
///
/// 关键点（实测 2026-10）：
/// - 评论是 **服务端直出** 在 HTML 里的，不需要评论接口，禁用 F12 也不影响。
/// - 页面里同时有「热门」`#commentTabBlockHot` 和「最新」`#commentTabBlockNew` 两个列表，
///   我们要的是「最新」，所以限定在 `#commentTabBlockNew` 内取。
/// - 每条评论正文：`.comment-main-list-item-content-comment`
/// - 评论时间：`.comment-main-list-item-content-info .content-info span`（第一个 span）
class SmzdmService {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 把用户粘贴的任意 smzdm 链接，归一化成标准「最新评论」地址：
  /// `https://www.smzdm.com/p/{页面ID}/p1/?sort_tab=new/#comments`
  ///
  /// 支持这些输入：
  /// - https://www.smzdm.com/p/184881376/  (任意 query)
  /// - https://www.smzdm.com/p/184881376/p1/?sort_tab=new/#comments
  /// - 只贴了 9 位页面 ID：184881376
  static String normalizeUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;

    // 1) 优先从路径 /p/<数字> 提取页面 ID
    var m = RegExp(r'/p/(\d+)').firstMatch(raw);
    // 2) 退而求其次：找孤立的 9 位数字（用户可能只贴了 ID）
    m ??= RegExp(r'(?:^|[^0-9])([0-9]{9})(?:[^0-9]|$)').firstMatch(raw);

    final id = m?.group(1);
    if (id != null && id.isNotEmpty) {
      return 'https://www.smzdm.com/p/$id/p1/?sort_tab=new/';
    }

    // 3) 实在找不到 ID，就原样使用（去掉锚点）
    return raw.split('#').first;
  }

  /// 抓取并解析「最新评论」，返回评论列表（正文 + 时间 + 9 位数字）。
  static Future<List<CommentItem>> fetchComments(String url) async {
    final target = normalizeUrl(url);
    final uri = Uri.tryParse(target);
    if (uri == null) throw Exception('链接格式不正确');

    final resp = await http.get(
      uri.replace(fragment: ''),
      headers: {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://www.smzdm.com/',
      },
    ).timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      throw Exception('网页返回状态码 ${resp.statusCode}');
    }

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final doc = html_parser.parse(body);

    // 限定「最新」列表；若页面结构变化则退回全局
    var items =
        doc.querySelectorAll('#commentTabBlockNew li.comment-main-list-item');
    if (items.isEmpty) {
      items = doc.querySelectorAll('li.comment-main-list-item');
    }
    if (items.isEmpty) {
      // 再兜底：直接找正文节点
      final bodies =
          doc.querySelectorAll('.comment-main-list-item-content-comment');
      final fallback = <CommentItem>[];
      for (final b in bodies) {
        final t = b.text.replaceAll(RegExp(r'\s+'), ' ').trim();
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
      final bodyEl = li.querySelector('.comment-main-list-item-content-comment');
      final text =
          (bodyEl?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;

      final timeEl = li.querySelector(
          '.comment-main-list-item-content-info .content-info span');
      final time = (timeEl?.text ?? '').trim();

      list.add(CommentItem(
        text: text,
        time: time,
        code: NumberFilter.collapseTo9(text),
      ));
    }
    return list;
  }
}
