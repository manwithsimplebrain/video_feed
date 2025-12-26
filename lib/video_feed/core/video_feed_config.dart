/// Configuration for the video feed module.
class VideoFeedConfig {
  const VideoFeedConfig({
    this.controllerPoolSize = 5,
    this.preloadAhead = 5,
    this.preloadBehind = 1,
    this.maxMemoryCacheMB = 150,
    this.maxStorageCacheMB = 1024,
    this.segmentSizeMB = 2,
    this.maxConcurrentDownloads = 3,
    this.fastScrollThreshold = 2,
    this.controllerInitTimeoutMs = 5000,
    this.loadMoreThreshold = 3,
  });

  /// Number of video controllers to keep in pool (LRU eviction).
  final int controllerPoolSize;

  /// Number of videos to preload ahead of current position.
  final int preloadAhead;

  /// Number of videos to keep cached behind current position.
  final int preloadBehind;

  /// Maximum memory cache size in megabytes.
  final int maxMemoryCacheMB;

  /// Maximum storage cache size in megabytes.
  final int maxStorageCacheMB;

  /// Video segment size in megabytes for chunked loading.
  final int segmentSizeMB;

  /// Maximum concurrent video downloads.
  final int maxConcurrentDownloads;

  /// Pages skipped threshold to trigger fast scroll mode.
  final int fastScrollThreshold;

  /// Timeout for controller initialization in milliseconds.
  final int controllerInitTimeoutMs;

  /// Trigger load more when this many videos from end.
  final int loadMoreThreshold;
}
