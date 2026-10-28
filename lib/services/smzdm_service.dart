import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

/// 负责抓取「什么值得买」详情页并解析出评论文本。
///
/// 关键结论（实测 2026-10）：
/// - smzdm 详情页的评论是 **服务端直出** 在 HTML 里的，
///   容器为 `#commentTabBlockNew > ul.comment-main-list`，
///   每条评论的 **正文** 节点是 `.comment-main-list-item-content-comment`。
/// - 不需要调所谓的评论接口；禁用浏览器 F12 调试也不影响，curl 直接能拿到。
/// - 一定要用桌面浏览器 UA，否则可能拿到精简页。
class SmzdmService {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 抓取详情页，返回按页面顺序的「评论文本」列表。
  static Future<List<String>> fetchComments(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) throw Exception('链接格式不正确');

    // 去掉 #comments 之类的锚点，避免请求异常
    final clean = uri.replace(fragment: '');

    final resp = await http.get(
      clean,
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

    // 强制按 UTF-8 解码，避免中文乱码
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final doc = html_parser.parse(body);

    // 评论正文节点（只含正文，不含昵称/时间/点赞数）
    var nodes = doc.querySelectorAll('.comment-main-list-item-content-comment');
    // 兜底：若页面结构变化，退回到整条评论容器
    if (nodes.isEmpty) {
      nodes = doc.querySelectorAll('.comment-main-list-item-content');
    }

    final texts = <String>[];
    for (final n in nodes) {
      final t = n.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) texts.add(t);
    }
    return texts;
  }
}
