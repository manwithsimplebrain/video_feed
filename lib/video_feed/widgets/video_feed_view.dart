import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preload_page_view/preload_page_view.dart' hide PageScrollPhysics;
import 'package:tiktok/video_item.dart';
import 'package:video_player/video_player.dart';

import '../core/video_cache_service.dart';
import '../core/video_feed_config.dart';
import '../services/controller_pool_service.dart';
import '../services/preload_manager.dart';
import '../utils/fast_scroll_detector.dart';
import 'video_player_surface.dart';

/// A TikTok-style vertical video feed with intelligent caching and preloading.
///
/// Features:
/// - LRU controller pool (configurable size, default 5)
/// - Bidirectional preloading (5 ahead, 1 behind)
/// - Fast scroll detection with aggressive cleanup
/// - App lifecycle management (pause on background)
/// - Load-more support for infinite scrolling
class VideoFeedView extends StatefulWidget {
  const VideoFeedView({
    super.key,
    required this.videos,
    required this.overlayBuilder,
    this.config = const VideoFeedConfig(),
    this.onPageChanged,
    this.onNeedMore,
    this.onVideoStateChanged,
    this.initialIndex = 0,
    this.physics,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// List of videos to display.
  final List<BaseVideoItem> videos;

  /// Configuration for caching and pooling.
  final VideoFeedConfig config;

  /// Builder for overlay widgets (like, share, comments, etc.).
  final Widget Function(
    BuildContext context,
    BaseVideoItem video,
    VideoPlayerController? controller,
  ) overlayBuilder;

  /// Callback when visible page changes.
  final ValueChanged<int>? onPageChanged;

  /// Callback to load more videos (infinite scroll).
  final Future<List<BaseVideoItem>> Function()? onNeedMore;

  /// Callback for video playback state changes.
  final void Function(String videoId, VideoPlaybackState state)?
      onVideoStateChanged;

  /// Initial page index.
  final int initialIndex;

  /// Scroll physics.
  final ScrollPhysics? physics;

  /// Custom loading indicator builder.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// Custom error widget builder.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<VideoFeedView> createState() => _VideoFeedViewState();
}

class _VideoFeedViewState extends State<VideoFeedView>
    with WidgetsBindingObserver {
  late final VideoCacheService _cacheService;
  late final ControllerPoolService _controllerPool;
  late final PreloadManager _preloadManager;
  late final FastScrollDetector _fastScrollDetector;
  late final PreloadPageController _pageController;

  List<BaseVideoItem> _videos = [];
  int _currentPage = 0;
  bool _isAppActive = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _videos = List.from(widget.videos);
    _currentPage = widget.initialIndex;

    // Initialize services
    _cacheService = VideoCacheService();
    _controllerPool = ControllerPoolService(
      config: widget.config,
      cacheService: _cacheService,
    );
    _preloadManager = PreloadManager(
      config: widget.config,
      cacheService: _cacheService,
      controllerPool: _controllerPool,
    );
    _fastScrollDetector = FastScrollDetector(
      threshold: widget.config.fastScrollThreshold,
    );

    _pageController = PreloadPageController(
      initialPage: widget.initialIndex,
    );

    _preloadManager.setVideos(_videos);

    // Initialize first video
    _initializeFirstVideo();
  }

  Future<void> _initializeFirstVideo() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_videos.isEmpty) return;
      await _preloadManager.onPageChanged(_currentPage);
      await _playCurrentVideo();
      if (mounted) setState(() {});
    });
  }

  Future<void> _handlePageChange(int newPage) async {
    final previousPage = _currentPage;
    _currentPage = newPage;

    // Detect fast scroll
    final isFastScroll = _fastScrollDetector.detect(previousPage, newPage);

    // Pause current video
    await _controllerPool.pauseAll();

    if (isFastScroll) {
      await _preloadManager.onFastScroll(newPage);
    } else {
      await _preloadManager.onPageChanged(newPage);
    }

    // Play new current video
    await _playCurrentVideo();

    widget.onPageChanged?.call(newPage);

    // Check if need to load more
    await _checkLoadMore(newPage);

    if (mounted) setState(() {});
  }

  Future<void> _playCurrentVideo() async {
    if (_videos.isEmpty || _currentPage >= _videos.length) return;

    final video = _videos[_currentPage];

    // Ensure controller is ready
    var controller = _controllerPool.getController(video.id);
    controller ??= await _controllerPool.acquireController(video);

    if (controller != null && _isAppActive) {
      await _controllerPool.play(video.id);
    }
  }

  Future<void> _checkLoadMore(int currentPage) async {
    if (_isLoadingMore) return;
    if (widget.onNeedMore == null) return;
    if (!_preloadManager.shouldLoadMore(currentPage)) return;

    _isLoadingMore = true;
    try {
      final moreVideos = await widget.onNeedMore!();
      if (moreVideos.isNotEmpty && mounted) {
        setState(() {
          _videos.addAll(moreVideos);
        });
        _preloadManager.setVideos(_videos);
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _isAppActive;
    _isAppActive = state == AppLifecycleState.resumed;

    if (_isAppActive && !wasActive) {
      _playCurrentVideo();
    } else if (!_isAppActive && wasActive) {
      _controllerPool.pauseAll();
    }
  }

  @override
  void didUpdateWidget(covariant VideoFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.videos, widget.videos)) {
      _videos = List.from(widget.videos);
      _preloadManager.setVideos(_videos);
      _preloadManager.onPageChanged(_currentPage);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _controllerPool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreloadPageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      itemCount: _videos.length,
      physics: widget.physics,
      preloadPagesCount: 1,
      onPageChanged: _handlePageChange,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final controller = _controllerPool.getController(video.id);

        return RepaintBoundary(
          child: VideoPlayerSurface(
            key: ValueKey(video.id),
            videoId: video.id,
            controller: controller,
            overlay: widget.overlayBuilder(context, video, controller),
            loadingBuilder: widget.loadingBuilder,
            errorBuilder: widget.errorBuilder,
            onStateChanged: (state) {
              widget.onVideoStateChanged?.call(video.id, state);
            },
          ),
        );
      },
    );
  }
}
