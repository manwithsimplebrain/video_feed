import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:tiktok/video_item.dart';
import 'package:tiktok/video_optimize.dart';
import 'package:video_player/video_player.dart';

class VideoFeedView extends StatefulWidget {
  const VideoFeedView({
    super.key,
    required this.videos,
    required this.overlayBuilder,
    this.onPageChanged,
    this.onNeedMore,
    this.maxControllerCache = 3,
    this.preloadAhead = 2,
    this.physics = const AlwaysScrollableScrollPhysics(),
  });

  /// The current videos to display
  final List<BaseVideoItem> videos;

  /// Overlay builder (ex: Like/Share)
  final Widget Function(BuildContext context, BaseVideoItem item)
  overlayBuilder;

  /// Video page change handler
  final ValueChanged<int>? onPageChanged;

  /// Load more videos handler
  final Future<List<BaseVideoItem>> Function()? onNeedMore;

  /// Number of video controller in cache
  final int maxControllerCache;

  /// Number of preload videos
  final int preloadAhead;

  /// Scroll behavior
  final ScrollPhysics physics;

  @override
  State<VideoFeedView> createState() => _VideoFeedViewState();
}

class _VideoFeedViewState extends State<VideoFeedView>
    with WidgetsBindingObserver {
  /// The current videos to display
  late List<BaseVideoItem> _videos = widget.videos;

  /// PageView controller
  final PreloadPageController _pageController = PreloadPageController();

  /// Current visible page
  int _currentPage = 0;

  /// Whether the app is currently active
  bool _isAppActive = true;

  /// LRU cache of video controllers by video ID
  final Map<String, VideoPlayerController> _controllerCache = {};

  /// Ordered list of video IDs by most recently accessed
  final List<String> _accessOrder = [];

  /// Set of video IDs currently being disposed to prevent race conditions
  final Set<String> _disposingControllers = {};

  final _preloadQueue = Queue<String>();
  final _preloadedFiles = <String, File>{};
  final _cacheManager = DefaultCacheManager();
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
  void didUpdateWidget(covariant VideoFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.videos, widget.videos)) {
      _videos = widget.videos;
      _manageControllerWindow(_currentPage);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _isAppActive;
    _isAppActive = state == AppLifecycleState.resumed;

    if (_isAppActive && !wasActive) {
      // App has come back to foreground
      _cleanupAndReinitializeCurrentVideo();
    } else if (!_isAppActive && wasActive) {
      // App is going to background - pause all videos
      _pauseAllControllers();
    }
  }

  /// Initialize the first video when the view loads
  void _initializeFirstVideo() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_videos.isEmpty) return;
      await _initAndPlayVideo(0);
      // Preload next videos
      _preloadNextVideos();
    });
  }

  /// Clean up and reinitialize the current video when coming back from background
  Future<void> _cleanupAndReinitializeCurrentVideo() async {
    if (_videos.isEmpty || _currentPage >= _videos.length) return;
    await _pauseAllControllers();

    final videoId = _videos[_currentPage].id;
    final controller = _controllerCache[videoId];

    // If controller exists but has errors, dispose it
    if (controller != null &&
        (controller.value.hasError || !controller.value.isInitialized)) {
      await _removeController(videoId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Reinitialize and play current video
    await _initAndPlayVideo(_currentPage);
  }

  /// Initialize and play a video at the given index
  Future<void> _initAndPlayVideo(int index) async {
    if (_videos.isEmpty || index >= _videos.length) return;

    final video = _videos[index];
    await _getOrCreateController(video);
    await _playController(video.id);

    if (mounted) setState(() {});
  }

  /// Touch a controller to mark it as recently used
  void _touchController(String videoId) {
    _accessOrder
      ..remove(videoId)
      ..add(videoId);
  }

  /// Get or create a controller for a video
  Future<VideoPlayerController?> _getOrCreateController(
    BaseVideoItem video,
  ) async {
    // Return the existing controller if available
    if (_controllerCache.containsKey(video.id)) {
      _touchController(video.id);
      return _controllerCache[video.id];
    }

    try {
      VideoPlayerController controller;

      // Check file into cache
      final cachedInfo = await _getCachedVideoFile(video.videoUrl);
      final hasCachedFile = cachedInfo != null;

      if (hasCachedFile) {
        // File into cache
        controller = VideoPlayerController.file(cachedInfo);
        _preloadedFiles[video.videoUrl] = cachedInfo;
      } else {
        // Load video from network
        controller = VideoPlayerController.networkUrl(
          Uri.parse(video.videoUrl),
        );

        // Cache file in background
        _loadVideoInBackground(video.videoUrl);
      }

      // Initialize the controller
      await controller.initialize();

      // Set looping
      await controller.setLooping(true);

      // Add to cache and update access order
      _controllerCache[video.id] = controller;
      _touchController(video.id);

      // Enforce cache size limit
      _enforceCacheLimit();
      return controller;
    } catch (e) {
      debugPrint('init controller failed: $e');
      return null;
    }
  }

  /// Play a controller if it exists and is initialized
  Future<void> _playController(String id) async {
    final c = _controllerCache[id];
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      try {
        await c.play();
      } catch (e) {
        debugPrint('play error: $e');
      }
    }
  }

  /// Pause all controllers
  Future<void> _pauseAllControllers() async {
    // Create a copy of the controllers to avoid concurrent modification
    final controllers = List<VideoPlayerController>.from(
      _controllerCache.values,
    );

    for (final c in controllers) {
      try {
        if (c.value.isInitialized && c.value.isPlaying) {
          await c.pause();
          await c.seekTo(Duration.zero);
        }
      } catch (e) {
        debugPrint('Error pausing video: $e');
      }
    }
  }

  /// Remove a controller from cache and dispose it
  Future<void> _removeController(String videoId) async {
    if (_disposingControllers.contains(videoId)) return;

    _disposingControllers.add(videoId);

    try {
      final controller = _controllerCache[videoId];
      if (controller != null) {
        // Remove from cache immediately
        _controllerCache.remove(videoId);
        _accessOrder.remove(videoId);

        // Pause and dispose
        try {
          if (controller.value.isInitialized) {
            await controller.pause();
          }
          await controller.dispose();
        } catch (e) {
          debugPrint('Error disposing controller: $e');
        }
      }
    } finally {
      _disposingControllers.remove(videoId);
    }
  }

  /// Enforce the cache size limit by removing least recently used controllers
  void _enforceCacheLimit() {
    while (_controllerCache.length > widget.maxControllerCache &&
        _accessOrder.isNotEmpty) {
      final oldest = _accessOrder.first;
      _removeController(oldest);
    }
  }

  /// Dispose all controllers
  Future<void> _disposeAllControllers() async {
    _pageController.dispose();

    final controllerIds = List<String>.from(_controllerCache.keys);
    for (final id in controllerIds) {
      await _removeController(id);
    }
    _controllerCache.clear();
    _accessOrder.clear();
  }

  /// Get cached video from video id
  Future<File?> _getCachedVideoFile(String videoUrl) async {
    if (_preloadedFiles.containsKey(videoUrl)) {
      return _preloadedFiles[videoUrl]!;
    }

    final fileInfo = await _cacheManager.getFileFromCache(videoUrl);
    return fileInfo?.file;
  }

  /// Load video file in background
  void _loadVideoInBackground(String videoUrl) {
    debugPrint("Start load video in BG: $videoUrl");
    if (_preloadQueue.contains(videoUrl) ||
        _preloadedFiles.containsKey(videoUrl)) {
      return;
    }

    _preloadQueue.add(videoUrl);
    _cacheManager
        .getSingleFile(videoUrl)
        .then((file) {
          debugPrint("Loaded video and cache in BG: $videoUrl");
          _preloadedFiles[videoUrl] = file;
        })
        .catchError((e) {
          debugPrint('background cache failed: $e');
        })
        .whenComplete(() {
          _preloadQueue.remove(videoUrl);
        });
  }

  /// Manage the window of controllers around the current page
  Future<void> _manageControllerWindow(int currentPage) async {
    if (_videos.isEmpty) return;

    // Define window of pages to keep
    final windowStart = (currentPage - 1).clamp(0, _videos.length - 1);
    final windowEnd = (currentPage + 1).clamp(0, _videos.length - 1);

    // Get IDs in window
    final idsToKeep = <String>{};
    for (int i = windowStart; i <= windowEnd; i++) {
      if (i < _videos.length) {
        idsToKeep.add(_videos[i].id);
      }
    }

    // Dispose controllers outside window
    final idsToDispose = _controllerCache.keys
        .where((id) => !idsToKeep.contains(id))
        .toList();
    for (final id in idsToDispose) {
      await _removeController(id);
    }

    // Initialize controllers in window, prioritizing current page
    if (currentPage < _videos.length) {
      // Current page first
      await _getOrCreateController(_videos[currentPage]);

      // Then previous page if in range
      if (windowStart < currentPage && windowStart >= 0) {
        await _getOrCreateController(_videos[windowStart]);
      }

      // Then next page if in range
      if (windowEnd > currentPage && windowEnd < _videos.length) {
        await _getOrCreateController(_videos[windowEnd]);
      }
    }
  }

  /// Handle page changes in the video feed
  Future<void> _handlePageChange(int newPage) async {
    if (_videos.isEmpty || newPage >= _videos.length) return;
    final previousPage = _currentPage;
    _currentPage = newPage;

    final isFastScroll = (newPage - previousPage).abs() > 1;

    await _pauseAllControllers();

    if (isFastScroll) {
      // In fast scroll, dispose all except target
      final videoId = _videos[newPage].id;
      final idsToDispose = List<String>.from(_controllerCache.keys);

      for (final id in idsToDispose) {
        if (id != videoId) {
          await _removeController(id);
        }
      }
    }

    // Manage the window controllers
    await _manageControllerWindow(newPage);

    // Play only the current video
    if (_videos.isNotEmpty && newPage < _videos.length) {
      await _initAndPlayVideo(newPage);
    }

    widget.onPageChanged?.call(newPage);

    // Trigger load more logic
    await onPageChanged(newPage);
  }

  Future<void> onPageChanged(int newPage) async {
    await _preloadNextVideos();

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
        _preloadNextVideos();
      }
    }
  }

  Future<void> _preloadNextVideos() async {
    if (_videos.isEmpty) return;
    final videosToPreload = _videos
        .skip(_currentPage + 1)
        .take(widget.preloadAhead)
        .map((v) => v.videoUrl)
        .where((url) => !_preloadedFiles.containsKey(url));

    for (final videoUrl in videosToPreload) {
      _loadVideoInBackground(videoUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PreloadPageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      itemCount: _videos.length,
      physics: widget.physics,
      onPageChanged: _handlePageChange,
      itemBuilder: (context, index) {
        final item = _videos[index];
        final controller = _controllerCache[item.id];
        return RepaintBoundary(
          child: VideoFeedViewOptimizedVideoPlayer(
            key: ValueKey(item.id),
            controller: controller,
            videoId: item.id,
          ),
        );
      },
    );
  }
}



