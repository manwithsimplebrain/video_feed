/// Video feed module with intelligent caching and preloading.
///
/// Usage:
/// ```dart
/// // In main.dart, initialize once before runApp:
/// await VideoCacheService.initialize(const VideoFeedConfig());
///
/// // Then use VideoFeedView in your widget tree:
/// VideoFeedView(
///   videos: myVideoList,
///   config: VideoFeedConfig(
///     controllerPoolSize: 5,
///     preloadAhead: 5,
///     preloadBehind: 1,
///   ),
///   overlayBuilder: (context, video, controller) {
///     return MyOverlayWidget(video: video);
///   },
///   onPageChanged: (index) => print('Page: $index'),
///   onNeedMore: () => fetchMoreVideos(),
/// )
/// ```
library;

// Core
export 'core/video_cache_service.dart';
export 'core/video_feed_config.dart';

// Models
export 'models/controller_entry.dart';

// Services
export 'services/controller_pool_service.dart';
export 'services/preload_manager.dart';

// Widgets
export 'widgets/video_feed_view.dart';
export 'widgets/video_player_surface.dart' show VideoPlaybackState;

// Utils
export 'utils/fast_scroll_detector.dart';
