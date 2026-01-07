import 'package:awesome_video_player/awesome_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:tiktok/video_cache_service.dart';
import 'package:tiktok/video_item.dart';
import 'package:tiktok/video_optimize.dart';

class VideoFeedView<T extends BaseVideoItem> extends StatefulWidget {
  const VideoFeedView({
    super.key,
    required this.videos,
    required this.overlayBuilder,
    this.onPageChanged,
    this.onNeedMore,
    this.maxControllerCache = 3,
    this.preloadAhead = 1,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.onEnterFullscreen,
  });

  final List<T> videos;
  final Widget Function(BuildContext context, T item) overlayBuilder;
  final ValueChanged<int>? onPageChanged;
  final Future<List<T>> Function()? onNeedMore;
  final int maxControllerCache;
  final int preloadAhead;
  final ScrollPhysics physics;
  final void Function(T video, BetterPlayerController controller)? onEnterFullscreen;

  @override
  State<VideoFeedView<T>> createState() => _VideoFeedViewState<T>();
}

class _VideoFeedViewState<T extends BaseVideoItem> extends State<VideoFeedView<T>>
    with WidgetsBindingObserver {
  late List<T> _videos = widget.videos;
  final PreloadPageController _pageController = PreloadPageController();
  int _currentPage = 0;
  bool _isAppActive = true;

  /// Controller cache - keeps prev + current + next
  final Map<String, BetterPlayerController> _controllers = {};

  /// Event listeners for each controller
  final Map<String, Function(BetterPlayerEvent)> _eventListeners = {};

  /// Set of video IDs currently being disposed
  final Set<String> _disposingControllers = {};

  /// Currently playing video ID
  String? _playingVideoId;

  bool _isPreloadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFirstVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeAllControllers();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoFeedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.videos, widget.videos)) {
      _videos = widget.videos;
      if (_currentPage < _videos.length) {
        _ensureControllersForPage(_currentPage);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _isAppActive;
    _isAppActive = state == AppLifecycleState.resumed;

    if (_isAppActive && !wasActive) {
      _playVideoAtCurrentPage();
    } else if (!_isAppActive && wasActive) {
      _pauseAllControllers();
    }
  }

  /// Initialize first video
  void _initializeFirstVideo() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_videos.isEmpty || !mounted) return;
      await _ensureControllersForPage(0);
      // _playVideoAtCurrentPage();
    });
  }

  bool _isHlsUrl(String url) => url.contains('.m3u8');
  
  bool _isDashUrl(String url) => url.contains('.mpd');

  bool _isControllerInitialized(BetterPlayerController? controller) {
    if (controller == null) return false;
    try {
      return controller.videoPlayerController?.value.initialized ?? false;
    } catch (e) {
      return false;
    }
  }

  bool _isControllerPlaying(BetterPlayerController? controller) {
    if (controller == null) return false;
    try {
      return controller.isPlaying() ?? false;
    } catch (e) {
      return false;
    }
  }

  void _pauseAllControllers() {
    for (final controller in _controllers.values) {
      try {
        if (_isControllerPlaying(controller)) {
          controller.pause();
        }
      } catch (e) {
        debugPrint('Error pausing controller: $e');
      }
    }
    _playingVideoId = null;
  }

  /// Dispose a specific controller
  Future<void> _disposeController(String videoId) async {
    if (_disposingControllers.contains(videoId)) return;
    _disposingControllers.add(videoId);

    try {
      final listener = _eventListeners.remove(videoId);
      final controller = _controllers.remove(videoId);

      if (controller != null) {
        // Remove listener trước
        if (listener != null) {
          try {
            controller.removeEventsListener(listener);
          } catch (e) {
            debugPrint('Remove events listener error: $e');
          }
        }

        try {
          // Pause và clear buffer trước khi dispose
          controller.pause();

          // Clear video player controller để release memory
          await controller.videoPlayerController?.seekTo(Duration.zero);
          await controller.videoPlayerController?.pause();

          // Đợi một chút để iOS release resources
          await Future<void>.delayed(const Duration(milliseconds: 100));

          controller.dispose();
          debugPrint('Disposed controller for $videoId');
        } catch (e) {
          debugPrint('Error disposing controller: $e');
        }
      }
    } finally {
      _disposingControllers.remove(videoId);
    }
  }

  /// Dispose all controllers
  Future<void> _disposeAllControllers() async {
    final ids = _controllers.keys.toList();
    for (final id in ids) {
      await _disposeController(id);
    }
    _controllers.clear();
    _eventListeners.clear();
    _playingVideoId = null;
  }

  /// Get IDs to keep for a given page index (prev + current + next)
  Set<String> _getIdsToKeep(int pageIndex) {
    final idsToKeep = <String>{};

    // Previous
    if (pageIndex > 0 && pageIndex - 1 < _videos.length) {
      idsToKeep.add(_videos[pageIndex - 1].id);
    }
    // Current
    if (pageIndex < _videos.length) {
      idsToKeep.add(_videos[pageIndex].id);
    }
    // Next
    if (pageIndex + 1 < _videos.length) {
      idsToKeep.add(_videos[pageIndex + 1].id);
    }

    return idsToKeep;
  }

  /// Clean up controllers that are not needed
  Future<void> _cleanupControllers(int currentIndex) async {
    if (_videos.isEmpty) return;

    final idsToKeep = _getIdsToKeep(currentIndex);

    final idsToDispose = _controllers.keys
        .where((id) => !idsToKeep.contains(id))
        .toList();

    for (final id in idsToDispose) {
      await _disposeController(id);
    }
  }

  /// Ensure controllers exist for prev, current, and next pages
  Future<void> _ensureControllersForPage(int pageIndex) async {
    if (_videos.isEmpty || !mounted) return;

    // Clean up old controllers first
    await _cleanupControllers(pageIndex);

    final currentVideoId = pageIndex < _videos.length ? _videos[pageIndex].id : null;

    // Create controllers for all needed videos
    for (int i = pageIndex - 1; i <= pageIndex + 1; i++) {
      if (i < 0 || i >= _videos.length) continue;

      final video = _videos[i];
      if (_controllers.containsKey(video.id)) continue;
      if (_disposingControllers.contains(video.id)) continue;

      // Only autoPlay for current page
      final isCurrentPage = video.id == currentVideoId;
      final controller = await _createController(video, autoPlay: isCurrentPage);

      if (controller != null && mounted) {
        _controllers[video.id] = controller;

        if (isCurrentPage) {
          _setupAutoPlayListener(video.id, controller);
        } else {
          _setupPrefetchListener(video.id, controller);
        }
      }
    }

    if (mounted) setState(() {});
  }

  /// Play video at current page
  void _playVideoAtCurrentPage() {
    if (_videos.isEmpty || _currentPage >= _videos.length) return;

    final video = _videos[_currentPage];
    final controller = _controllers[video.id];

    if (controller == null) return;

    _playingVideoId = video.id;

    if (_isControllerInitialized(controller)) {
      if (!_isControllerPlaying(controller)) {
        try {
          controller.play();
        } catch (e) {
          debugPrint('Error playing video: $e');
        }
      }
    }
    // If not initialized, the listener will play when ready
  }

  /// Tạo data source - dùng proxy cho video đang play, direct cho prefetch
  BetterPlayerDataSource _createDataSource(String videoUrl, {bool useProxy = false}) {
    final isHls = _isHlsUrl(videoUrl);
    final isDash = _isDashUrl(videoUrl);

    // Chỉ dùng proxy khi video đang play VÀ proxy available
    String playUrl = videoUrl;
    if (useProxy && VideoCacheService.instance.shouldUseProxy()) {
      playUrl = VideoCacheService.instance.getPlayUrl(videoUrl);
    }

    // Tắt BetterPlayer cache (dùng proxy cache thay thế)
    const cacheConfig = BetterPlayerCacheConfiguration(useCache: false);

    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      playUrl,
      cacheConfiguration: cacheConfig,
      videoFormat: isHls
          ? BetterPlayerVideoFormat.hls
          : isDash
              ? BetterPlayerVideoFormat.dash
              : null,
      // Buffer configuration tối ưu cho RAM
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 1500,           // 1.5s minimum
        maxBufferMs: 8000,           // 8s max buffer - giảm RAM
        bufferForPlaybackMs: 1000,   // Start play sau 1s
        bufferForPlaybackAfterRebufferMs: 2000,
      ),
    );
  }

  Future<BetterPlayerController?> _createController(
    T video, {
    required bool autoPlay,
  }) async {
    try {
      // Chỉ dùng proxy khi video đang play (autoPlay = true)
      // Video prefetch dùng direct URL để không gây lag
      final dataSource = _createDataSource(video.videoUrl, useProxy: autoPlay);

      final config = BetterPlayerConfiguration(
        autoPlay: autoPlay,
        looping: true,
        aspectRatio: 9/16,
        fit: BoxFit.contain,
        handleLifecycle: false,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      );

      final controller = BetterPlayerController(
        config,
        betterPlayerDataSource: dataSource,
      );

      // Listen for errors to handle HLS issues
      controller.addEventsListener((event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          debugPrint('Video error for ${video.id}: ${event.parameters}');
          // Try to recover by seeking to current position
          _tryRecoverFromError(video.id, controller);
        }
      });

      debugPrint('Created controller for ${video.id} (autoPlay: $autoPlay, proxy: $autoPlay)');
      return controller;
    } catch (e) {
      debugPrint('Error creating controller: $e');
      return null;
    }
  }

  /// Try to recover from playback error
  void _tryRecoverFromError(String videoId, BetterPlayerController controller) {
    if (!mounted || _playingVideoId != videoId) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _playingVideoId != videoId) return;

      try {
        final position = controller.videoPlayerController?.value.position;
        if (position != null) {
          debugPrint('Attempting to recover video $videoId at position $position');
          await controller.seekTo(position);
          await controller.play();
        }
      } catch (e) {
        debugPrint('Recovery failed: $e');
      }
    });
  }

  /// Setup listener for auto-play when video is initialized
  void _setupAutoPlayListener(String videoId, BetterPlayerController controller) {
    _removeListener(videoId);

    if (_isControllerInitialized(controller)) {
      if (!_isControllerPlaying(controller) && _playingVideoId == videoId) {
        try {
          controller.play();
        } catch (e) {
          debugPrint('Error playing video: $e');
        }
      }
      return;
    }

    void listener(BetterPlayerEvent event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        debugPrint('Video $videoId initialized');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playingVideoId == videoId && _controllers.containsKey(videoId)) {
            try {
              controller.play();
              // setState(() {});
            } catch (e) {
              debugPrint('Error playing after init: $e');
            }
        }
        });
      }
    }

    _eventListeners[videoId] = listener;
    controller.addEventsListener(listener);
  }

  /// Setup listener for prefetched video
  void _setupPrefetchListener(String videoId, BetterPlayerController controller) {
    _removeListener(videoId);

    void listener(BetterPlayerEvent event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        debugPrint('Prefetched video $videoId is ready');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // if (mounted) setState(() {});
        });
      }
    }

    _eventListeners[videoId] = listener;
    controller.addEventsListener(listener);
  }

  void _removeListener(String videoId) {
    final oldListener = _eventListeners.remove(videoId);
    if (oldListener != null) {
      final controller = _controllers[videoId];
      if (controller != null) {
        try {
          controller.removeEventsListener(oldListener);
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  Future<void> _handlePageChange(int newPage) async {
    if (_videos.isEmpty || newPage >= _videos.length || !mounted) return;
    if (newPage == _currentPage) return;

    debugPrint('Page changed: $_currentPage -> $newPage');

    _currentPage = newPage;

    // Pause all videos first
    _pauseAllControllers();

    // Check if we have a ready controller
    final newVideo = _videos[newPage];
    final existingController = _controllers[newVideo.id];

    if (existingController != null && _isControllerInitialized(existingController)) {
      // Controller is ready, play immediately
      debugPrint('Using ready controller for ${newVideo.id}');
      _playingVideoId = newVideo.id;
      try {
        await existingController.seekTo(Duration.zero);
        existingController.play();
      } catch (e) {
        debugPrint('Error playing video: $e');
      }
      if (mounted) setState(() {});

      // Ensure controllers for new window (prev + current + next)
      _ensureControllersForPage(newPage);
    } else if (existingController != null) {
      // Controller exists but not initialized yet - set up listener and wait
      debugPrint('Controller exists but not ready for ${newVideo.id}');
      _playingVideoId = newVideo.id;
      _setupAutoPlayListener(newVideo.id, existingController);
      if (mounted) setState(() {});

      _ensureControllersForPage(newPage);
    } else {
      // No controller - need to create
      debugPrint('Creating new controller for ${newVideo.id}');
      _playingVideoId = newVideo.id;
      await _ensureControllersForPage(newPage);
      _playVideoAtCurrentPage();
    }

    widget.onPageChanged?.call(newPage);
    await _onPageChangedInternal(newPage);
  }

  Future<void> _onPageChangedInternal(int newPage) async {
    final needMore = widget.onNeedMore;
    if (!_isPreloadingMore &&
        needMore != null &&
        newPage >= _videos.length - 2) {
      _isPreloadingMore = true;
      final more = await needMore();
      _isPreloadingMore = false;
      if (mounted && more.isNotEmpty) {
        setState(() {
          _videos = [..._videos, ...more];
        });
        // Prefetch next after loading more
        _ensureControllersForPage(_currentPage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PreloadPageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      itemCount: _videos.length,
      preloadPagesCount: 1,
      physics: widget.physics,
      onPageChanged: _handlePageChange,
      itemBuilder: (context, index) {
        final item = _videos[index];
        final controller = _controllers[item.id];
        return RepaintBoundary(
          child: VideoFeedViewOptimizedVideoPlayer(
            key: ValueKey(item.id),
            controller: controller,
            videoId: item.id,
            onEnterFullscreen: controller != null
                ? () => widget.onEnterFullscreen?.call(item, controller)
                : null,
          ),
        );
      },
    );
  }
}

// Keeping for backwards compatibility
class _VideoPlayerSurface extends StatefulWidget {
  const _VideoPlayerSurface({
    required this.controller,
    required this.overlay,
  });

  final BetterPlayerController? controller;
  final Widget overlay;

  @override
  State<_VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<_VideoPlayerSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loadingCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _loadingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    bool isInitialized = false;
    try {
      isInitialized = c?.videoPlayerController?.value.initialized ?? false;
    } catch (e) {
      isInitialized = false;
    }

    if (c == null || !isInitialized) {
      return Center(
        child: RotationTransition(
          turns: Tween<double>(begin: 0, end: 1).animate(_loadingCtrl),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return BetterPlayer(controller: c);
  }
}
