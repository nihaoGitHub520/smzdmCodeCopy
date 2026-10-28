/// App 显示名（桌面图标 / 标题栏统一用这个）
const String kAppName = '多多福袋助手';

/// 发现页：从这里取「最新爆料」列表，取第一个条目的页面 ID
/// （如失效可在 App 的「更多设置」里改成别的发现页链接）
const String kDiscoverUrl = 'https://faxian.smzdm.com/h2s8645t0f0c0p1/';

/// 从发现页最多缓存多少条爆料（第一个没评论时可点「下一条」往后翻）
const int kDiscoverFeedLimit = 10;

/// 默认监控链接（最新评论排序页，评论为服务端直出，可直接解析）
const String kDefaultUrl =
    'https://www.smzdm.com/p/184881376/p1/?sort_tab=new/';

/// 列表里最多展示多少条评论
const int kMaxShowComments = 12;

// ---------------------------------------------------------------------------
// 本地存储（shared_preferences）key
// ---------------------------------------------------------------------------

/// 当前监控的商品链接
const String kPrefUrl = 'monitor_url';

/// 发现页链接
const String kPrefDiscoverUrl = 'discover_url';

// ---------------------------------------------------------------------------
// 拼多多搜索
// ---------------------------------------------------------------------------

/// 拼多多 App 深链：search_key 用该行提取出的 9 位码
///
/// 形如 pinduoduo://yangkeduo.com/search_result.html?search_key=233100271
String pddSearchUrl(String keyword) {
  final key = Uri.encodeComponent(keyword.trim());
  return 'pinduoduo://yangkeduo.com/search_result.html?search_key=$key';
}

/// 兜底：拼多多 H5 搜索页（未装 App 或深链打不开时用）
String pddWebUrl(String keyword) {
  final key = Uri.encodeComponent(keyword.trim());
  return 'https://mobile.yangkeduo.com/search_result.html?search_key=$key';
}
