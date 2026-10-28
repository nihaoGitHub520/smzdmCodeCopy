import '../models/number_item.dart';

/// 数字过滤与提取逻辑（纯 Dart，不依赖平台，方便单测）
///
/// 规则（按你的要求）：把一段评论里的 **所有非数字字符全部去掉**
/// （空格、中文、标点、表情都去掉），剩下的如果 **恰好 9 位** 才算有效。
///
/// 这样 `233100 271`、`232483 598还没拼成功` 这类评论都能正确得到 9 位数字。
class NumberFilter {
  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  /// 整段文字去掉所有非数字后，若恰好 9 位则返回该数字，否则返回 null。
  static String? collapseTo9(String text) {
    final digits = text.replaceAll(_nonDigit, '');
    return digits.length == 9 ? digits : null;
  }

  /// 从一批评论文本里按顺序提取有效 9 位数字，自动去重，最多取 [max] 个。
  static List<NumberItem> extractFromComments(
    List<String> comments, {
    int max = 5,
  }) {
    final result = <NumberItem>[];
    final seen = <String>{};
    for (final c in comments) {
      final v = collapseTo9(c);
      if (v != null && seen.add(v)) {
        result.add(NumberItem(value: v, source: c));
        if (result.length >= max) break;
      }
    }
    return result;
  }
}
