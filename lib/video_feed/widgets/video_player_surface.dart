import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

/// Playback state enumeration.
enum VideoPlaybackState {
  loading,
  playing,
  paused,
  buffering,
  error,
}

/// Optimized video player widget with smart state management.
class VideoPlayerSurface extends StatefulWidget {
  const VideoPlayerSurface({
    super.key,
    required this.videoId,
    required this.controller,
    required this.overlay,
    this.loadingBuilder,
    this.errorBuilder,
    this.onStateChanged,
  });

  final String videoId;
  final VideoPlayerController? controller;
  final Widget overlay;
  final Widget Function(BuildContext)? loadingBuilder;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final void Function(VideoPlaybackState)? onStateChanged;

  @override
  State<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<VideoPlayerSurface>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _trackedController;
  bool _isBuffering = false;
  bool _isPlaying = false;
  bool _hasError = false;
  Key _surfaceKey = UniqueKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _trackController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != _trackedController) {
      _untrackController();
      _trackController(widget.controller);
      _surfaceKey = UniqueKey();
    }
  }

  void _trackController(VideoPlayerController? controller) {
    _trackedController = controller;
    controller?.addListener(_onControllerUpdate);
    _syncState();
  }

  void _untrackController() {
    _trackedController?.removeListener(_onControllerUpdate);
  }

  void _syncState() {
    final c = _trackedController;
    if (c != null && c.value.isInitialized) {
      _isBuffering = c.value.isBuffering;
      _isPlaying = c.value.isPlaying;
      _hasError = c.value.hasError;
    } else {
      _isBuffering = false;
      _isPlaying = false;
      _hasError = false;
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    final c = _trackedController;
    if (c == null) return;

    final wasBuffering = _isBuffering;
    final wasPlaying = _isPlaying;
    final hadError = _hasError;

    _syncState();

    // Smart buffering: hide indicator if video is playing and has content
    bool showBuffering = _isBuffering;
    if (c.value.isPlaying && c.value.position > Duration.zero) {
      showBuffering = false;
    }
    if (c.value.position > Duration.zero &&
        c.value.duration.inMilliseconds > 0) {
      showBuffering = false;
    }
    _isBuffering = showBuffering;

    // Only rebuild if state actually changed
    if (_isBuffering != wasBuffering ||
        _isPlaying != wasPlaying ||
        _hasError != hadError) {
      // Use post-frame callback to avoid setState during build
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });

      _notifyStateChange();
    }
  }

  void _notifyStateChange() {
    if (widget.onStateChanged == null) return;

    final c = _trackedController;
    VideoPlaybackState state;

    if (c == null || !c.value.isInitialized) {
      state = VideoPlaybackState.loading;
    } else if (c.value.hasError) {
      state = VideoPlaybackState.error;
    } else if (_isBuffering) {
      state = VideoPlaybackState.buffering;
    } else if (c.value.isPlaying) {
      state = VideoPlaybackState.playing;
    } else {
      state = VideoPlaybackState.paused;
    }

    widget.onStateChanged!(state);
  }

  @override
  void dispose() {
    _untrackController();
    super.dispose();
  }

  void _togglePlayPause() {
    final c = _trackedController;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final controller = widget.controller;

    // Loading state
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          widget.loadingBuilder?.call(context) ??
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
        ],
      );
    }

    // Error state
    if (controller.value.hasError) {
      return widget.errorBuilder?.call(
            context,
            controller.value.errorDescription ?? 'Unknown error',
          ) ??
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.error, color: Colors.red, size: 48),
                SizedBox(height: 8),
                Text(
                  'Failed to load video',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
    }

    // Video player
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video surface
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller, key: _surfaceKey),
              ),
            ),

            // Buffering indicator
            if (_isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),

            // Play/pause indicator
            if (!_isPlaying)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),

            // Overlay (likes, comments, etc.)
            Positioned.fill(
              child: IgnorePointer(child: widget.overlay),
            ),
          ],
        ),
      ),
    );
  }
}
