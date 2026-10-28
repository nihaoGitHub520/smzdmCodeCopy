/// 默认监控链接（最新评论排序页，评论为服务端直出，可直接解析）
const String kDefaultUrl =
    'https://www.smzdm.com/p/184881376/p1/?sort_tab=new/';

// ---------------------------------------------------------------------------
// 本地存储（shared_preferences）key
// ---------------------------------------------------------------------------

/// 监控链接
const String kPrefUrl = 'monitor_url';

/// 悬浮窗是否显示（用户可开关，默认开）
const String kPrefOverlayEnabled = 'overlay_enabled';

/// 悬浮窗宽度（dp）
const String kPrefOverlayWidth = 'overlay_width';

/// 悬浮窗高度（dp）
const String kPrefOverlayHeight = 'overlay_height';

// ---------------------------------------------------------------------------
// 悬浮窗默认尺寸与上下限（单位：dp，与 flutter_overlay_window 的 height/width 一致）
// ---------------------------------------------------------------------------

const int kOverlayDefaultWidth = 330;
const int kOverlayDefaultHeight = 420;

const int kOverlayMinWidth = 200;
const int kOverlayMinHeight = 180;

/// 单个按钮调整尺寸时的步长（dp）
const int kOverlayStep = 30;

/// 悬浮窗里列表最多展示多少条评论（超出可滚动）
const int kMaxShowComments = 12;

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
