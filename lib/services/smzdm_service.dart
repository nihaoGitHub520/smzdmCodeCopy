import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// 负责抓取「什么值得买」详情页并解析出评论文本。
/// 关键点：smzdm 有反爬，必须伪装成桌面浏览器（User-Agent）才容易拿到正文。
class SmzdmService {
  // 桌面 Chrome 的 UA，避免被当成爬虫拦掉
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 抓取详情页，返回按页面顺序的「评论文本」列表（里面会混着无关评论，过滤在外层做）。
  static Future<List<String>> fetchComments(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('链接格式不正确');

    final resp = await http
        .get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('网页返回状态码 ${resp.statusCode}');
    }

    // http 包已按响应头编码解码为字符串
    final doc = html_parser.parse(resp.body);
    return _extractCommentTexts(doc);
  }

  /// 从解析后的页面 DOM 里提取评论文本，分三层防御：
  /// 1) 优先用 smzdm 评论容器的具体选择器（社区脚本验证过）
  /// 2) 退而求其次：抓整个评论区容器，再按行拆成单条评论
  /// 3) 最后兜底：扫描页面里长度合适的文本块（粗略，可能包含非评论）
  static List<String> _extractCommentTexts(Document doc) {
    final specificSelectors = [
      '.comment-main-list-item-content',
      '#commentTabBlockNew .comment-main-list-item-content',
      '.comment-list .comment-content',
    ];
    for (final sel in specificSelectors) {
      final blocks = doc.querySelectorAll(sel);
      if (blocks.isNotEmpty) {
        final texts = <String>[];
        for (final block in blocks) {
          final t = block.text.trim();
          if (t.isNotEmpty) texts.add(t);
        }
        if (texts.isNotEmpty) return texts;
      }
    }

    // 第二层：整块评论区按行拆
    final container = doc.querySelector('#commentTabBlockNew');
    if (container != null) {
      return container.text
          .split(RegExp(r'[\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    // 第三层：兜底扫描
    final fallback = <String>[];
    doc.body?.querySelectorAll('p, div, span, li').forEach((e) {
      final t = e.text.trim();
      if (t.length >= 5 && t.length <= 200) fallback.add(t);
    });
    return fallback;
  }
}
