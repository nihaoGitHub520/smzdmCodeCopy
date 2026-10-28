/// 发现页（最新爆料）里的一个条目
class DiscoverItem {
  /// 页面 ID，如 184902762（对应 https://www.smzdm.com/p/184902762/）
  final String id;

  /// 标题，如「百亿补贴：索尼 耳机LinkBuds Open ...」
  final String title;

  /// 商城名，如「拼多多」
  final String mall;

  /// 价格文案，如「402元（需用券）」
  final String price;

  /// 爆料时间，如「09:19」
  final String time;

  DiscoverItem({
    required this.id,
    required this.title,
    required this.mall,
    required this.price,
    required this.time,
  });
}
