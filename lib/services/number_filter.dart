import '../models/number_item.dart';

/// 数字过滤与提取逻辑（纯 Dart，不依赖平台，方便单测）
class NumberFilter {
  // 严格规则：整串必须恰好是 9 位数字（去空格后）
  static final RegExp _nineDigits = RegExp(r'^\d{9}$');

  /// 对单条评论做严格判断：
  /// 先去掉所有空白（空格/换行/制表符），再判断是不是「纯 9 位数字」。
  /// 返回 9 位数字字符串表示有效；返回 null 表示这条评论无关。
  static String? extractStrict(String comment) {
    final noSpace = comment.replaceAll(RegExp(r'\s+'), '');
    if (_nineDigits.hasMatch(noSpace)) return noSpace;
    return null;
  }

  /// 从一批评论文本里，按出现顺序提取有效的 9 位数字。
  /// [max] 控制最多取几条（弹窗只显示最近 5 个）。自动去重。
  static List<NumberItem> extractFromComments(List<String> comments,
      {int max = 5}) {
    final result = <NumberItem>[];
    for (final c in comments) {
      final v = extractStrict(c);
      if (v != null && !result.any((e) => e.value == v)) {
        result.add(NumberItem(value: v, source: c));
        if (result.length >= max) break;
      }
    }
    return result;
  }
}
