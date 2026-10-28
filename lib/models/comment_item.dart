/// 单条评论：正文 + 时间 + （若有）9 位数字
class CommentItem {
  final String text; // 评论正文
  final String time; // 评论时间，如「刚刚」「3分钟前」「9小时前」
  final String? code; // 正文里去掉非数字后恰好 9 位的数字（没有则 null）

  CommentItem({required this.text, required this.time, this.code});
}
