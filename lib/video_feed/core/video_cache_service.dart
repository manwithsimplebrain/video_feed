import 'package:flutter/foundation.dart';
import 'package:flutter_video_caching/flutter_video_caching.dart';

import 'video_feed_config.dart';

/// Service wrapper for flutter_video_caching functionality.
class VideoCacheService {
  static bool _initialized = false;

  /// Initialize VideoProxy - call once in main() before runApp.
  static Future<void> initialize(VideoFeedConfig config) async {
    if (_initialized) return;

    await VideoProxy.init();

    _initialized = true;
  }

  /// Check if the cache service has been initialized.
  static bool get isInitialized => _initialized;

  /// Convert a video URL to a cached local proxy URL.
  Uri getProxiedUrl(String videoUrl) {
    return videoUrl.toLocalUri();
  }

  /// Precache a video for later playback.
  Future<void> precache(
    String videoUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      await VideoCaching.precache(videoUrl, headers: headers);
    } catch (e) {
      debugPrint('VideoCacheService: precache failed for $videoUrl: $e');
    }
  }

  /// Check if video is fully cached.
  Future<bool> isCached(String videoUrl, {Map<String, String>? headers}) async {
    try {
      return await VideoCaching.isCached(videoUrl, headers: headers);
    } catch (e) {
      debugPrint('VideoCacheService: isCached check failed: $e');
      return false;
    }
  }

  /// Precache multiple videos in priority order.
  Future<void> precacheMultiple(
    List<String> urls, {
    Map<String, String>? headers,
  }) async {
    for (final url in urls) {
      await precache(url, headers: headers);
    }
  }

  /// Clear specific cached video.
  Future<void> clearCache(String videoUrl) async {
    try {
      LruCacheSingleton().removeCacheByUrl(videoUrl);
    } catch (e) {
      debugPrint('VideoCacheService: clearCache failed: $e');
    }
  }

  /// Clear all cached videos.
  Future<void> clearAllCache() async {
    try {
      LruCacheSingleton().removeCacheByUrl('', singleFile: false);
    } catch (e) {
      debugPrint('VideoCacheService: clearAllCache failed: $e');
    }
  }
}
