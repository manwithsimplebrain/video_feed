import 'dart:async';

import 'package:tiktok/video_item.dart';

import '../core/video_cache_service.dart';
import '../core/video_feed_config.dart';
import 'controller_pool_service.dart';

/// Manages bidirectional video preloading with sliding window.
class PreloadManager {
  PreloadManager({
    required this.config,
    required this.cacheService,
    required this.controllerPool,
  });

  final VideoFeedConfig config;
  final VideoCacheService cacheService;
  final ControllerPoolService controllerPool;

  List<BaseVideoItem> _videos = [];
  int _currentIndex = 0;
  bool _isUpdating = false;

  /// Update the video list.
  void setVideos(List<BaseVideoItem> videos) {
    _videos = videos;
  }

  /// Get current index.
  int get currentIndex => _currentIndex;

  /// Calculate window bounds for given index.
  ({int start, int end, Set<String> ids}) _calculateWindow(int index) {
    if (_videos.isEmpty) {
      return (start: 0, end: 0, ids: <String>{});
    }

    final start = (index - config.preloadBehind).clamp(0, _videos.length - 1);
    final end = (index + config.preloadAhead).clamp(0, _videos.length - 1);

    final ids = <String>{};
    for (int i = start; i <= end; i++) {
      ids.add(_videos[i].id);
    }

    return (start: start, end: end, ids: ids);
  }

  /// Update window when page changes.
  Future<void> onPageChanged(int newIndex) async {
    if (_isUpdating) return;
    if (_videos.isEmpty) return;

    _isUpdating = true;
    _currentIndex = newIndex;

    try {
      final window = _calculateWindow(newIndex);

      // Release controllers outside the window
      await controllerPool.releaseControllersExcept(window.ids);

      // Preload in priority order
      await _preloadWindow(newIndex, window);
    } finally {
      _isUpdating = false;
    }
  }

  /// Preload videos in the current window.
  Future<void> _preloadWindow(
    int currentIndex,
    ({int start, int end, Set<String> ids}) window,
  ) async {
    // 1. Ensure current video controller is ready
    if (currentIndex < _videos.length) {
      final currentVideo = _videos[currentIndex];
      await controllerPool.acquireController(currentVideo);
    }

    // 2. Precache file data for upcoming videos (async, non-blocking)
    final aheadUrls = <String>[];
    for (int i = currentIndex + 1;
        i <= currentIndex + config.preloadAhead && i < _videos.length;
        i++) {
      aheadUrls.add(_videos[i].videoUrl);
    }

    // Fire and forget file precaching
    unawaited(cacheService.precacheMultiple(aheadUrls));

    // 3. Prepare controllers for immediate neighbors
    // Current is done, now do +1 and -1
    for (int offset = 1; offset <= 2; offset++) {
      // Next
      final nextIdx = currentIndex + offset;
      if (nextIdx < _videos.length && nextIdx <= window.end) {
        final nextVideo = _videos[nextIdx];
        if (!controllerPool.hasController(nextVideo.id)) {
          await controllerPool.acquireController(nextVideo);
        }
      }

      // Previous (only within preloadBehind limit)
      if (offset <= config.preloadBehind) {
        final prevIdx = currentIndex - offset;
        if (prevIdx >= 0 && prevIdx >= window.start) {
          final prevVideo = _videos[prevIdx];
          if (!controllerPool.hasController(prevVideo.id)) {
            await controllerPool.acquireController(prevVideo);
          }
        }
      }
    }
  }

  /// Handle fast scroll - aggressive cleanup, keep only target.
  Future<void> onFastScroll(int targetIndex) async {
    if (_videos.isEmpty || targetIndex >= _videos.length) return;

    _currentIndex = targetIndex;
    final targetVideo = _videos[targetIndex];

    // Release all except target
    await controllerPool.releaseControllersExcept({targetVideo.id});

    // Acquire target controller
    await controllerPool.acquireController(targetVideo);
  }

  /// Check if should trigger load more.
  bool shouldLoadMore(int currentIndex) {
    return currentIndex >= _videos.length - config.loadMoreThreshold;
  }

  /// Get video by ID.
  BaseVideoItem? getVideoById(String id) {
    try {
      return _videos.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get video at index.
  BaseVideoItem? getVideoAt(int index) {
    if (index < 0 || index >= _videos.length) return null;
    return _videos[index];
  }
}
