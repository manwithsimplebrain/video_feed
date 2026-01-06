import 'package:awesome_video_player/awesome_video_player.dart';
import 'package:flutter/material.dart';

class VideoFeedViewOptimizedVideoPlayer extends StatefulWidget {
  const VideoFeedViewOptimizedVideoPlayer({required this.controller, required this.videoId, super.key});

  final BetterPlayerController? controller;
  final String videoId;

  @override
  State<VideoFeedViewOptimizedVideoPlayer> createState() => _VideoFeedViewOptimizedVideoPlayerState();
}

class _VideoFeedViewOptimizedVideoPlayerState extends State<VideoFeedViewOptimizedVideoPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _loadingController;
  bool _isBuffering = false;
  BetterPlayerController? _oldController;
  String? _currentVideoId;
  bool _isPlaying = false;
  Key _playerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _oldController = widget.controller;
    _currentVideoId = widget.videoId;
    _addControllerListener();
  }

  void _addControllerListener() {
    try {
      final videoController = widget.controller?.videoPlayerController;
      if (videoController != null) {
        _isBuffering = videoController.value.isBuffering;
        _isPlaying = videoController.value.isPlaying;
        videoController.addListener(_onControllerUpdate);
      }
    } catch (e) {
      debugPrint('Error adding controller listener: $e');
    }
  }

  void _removeControllerListener(BetterPlayerController? controller) {
    try {
      controller?.videoPlayerController?.removeListener(_onControllerUpdate);
    } catch (e) {
      // Controller may be disposed, ignore
    }
  }

  @override
  void didUpdateWidget(VideoFeedViewOptimizedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool videoIdChanged = widget.videoId != _currentVideoId;
    final bool controllerChanged = widget.controller != _oldController;

    if (videoIdChanged || controllerChanged) {
      _removeControllerListener(_oldController);
      _oldController = widget.controller;
      _currentVideoId = widget.videoId;
      _playerKey = UniqueKey();
      _addControllerListener();

      // Schedule the setState for the next frame to avoid build errors
      bool shouldUpdateBuffering = false;
      try {
        shouldUpdateBuffering = widget.controller?.videoPlayerController?.value.isBuffering ?? false;
      } catch (e) {
        // Controller may be disposed
      }

      if (mounted && _isBuffering != shouldUpdateBuffering) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isBuffering = shouldUpdateBuffering;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _removeControllerListener(_oldController);
    _oldController = null;
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    try {
      final videoController = widget.controller?.videoPlayerController;
      if (videoController == null) return;

      if (widget.videoId != _currentVideoId) return;

      // Check if controller is disposed or in error state
      if (videoController.value.hasError) {
        // Schedule UI update for next frame to avoid build conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isBuffering = false);
        });
        return;
      }

      final isBuffering = videoController.value.isBuffering;
      final isPlaying = videoController.value.isPlaying;

      // Hide buffering indicator if:
      // 1. Video is actually playing and has advanced
      // 2. Video has loaded content (position > 0)
      // 3. Video duration is known and valid
      bool shouldShowBuffering = isBuffering;
      if ((isPlaying && videoController.value.position > Duration.zero) ||
          (videoController.value.position > Duration.zero && (videoController.value.duration?.inMilliseconds ?? 0) > 0)) {
        shouldShowBuffering = false;
      }

      // Only update state if something changed
      if (_isBuffering != shouldShowBuffering || _isPlaying != isPlaying) {
        // Use post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isBuffering = shouldShowBuffering;
              _isPlaying = isPlaying;
            });
          }
        });
      }
    } catch (e) {
      // Controller may be disposed, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    bool isInitialized = false;
    try {
      isInitialized = controller?.videoPlayerController?.value.initialized ?? false;
    } catch (e) {
      isInitialized = false;
    }

    if (controller == null || !isInitialized) {
      return Center(
        child: RotationTransition(
          turns: Tween<double>(begin: 0, end: 1).animate(_loadingController),
          child: const CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final videoController = controller.videoPlayerController;

    return GestureDetector(
      onTap: () {
        try {
          if (controller.isPlaying() ?? false) {
            controller.pause();
          } else {
            controller.play();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        } catch (e) {
          debugPrint('Error toggling playback: $e');
        }
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                key: _playerKey,
                fit: BoxFit.contain,
                child: SizedBox(
                  width: videoController?.value.size?.width ?? 1920,
                  height: videoController?.value.size?.height ?? 1080,
                  child: BetterPlayer(controller: controller),
                ),
              ),
              if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
