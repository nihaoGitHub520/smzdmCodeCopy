/// 一个被提取出来的、有效的 9 位数字条目
class NumberItem {
  final String value; // 9 位纯数字
  final String source; // 原始评论文本（方便追溯这个数字来自哪条评论）

  NumberItem({required this.value, required this.source});
}
