import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tiktok/video_feed/services/controller_pool_service.dart';
import 'package:tiktok/video_feed/widgets/video_player_surface.dart';
import 'package:tiktok/video_item.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class VideoGridWidget extends StatefulWidget {
  const VideoGridWidget({
    super.key,
    required this.videos,
    required this.controllerPool,
    required this.onVideoTap,
  });

  final List<BaseVideoItem> videos;
  final ControllerPoolService controllerPool;
  final void Function(BaseVideoItem) onVideoTap;

  @override
  State<VideoGridWidget> createState() => _VideoGridWidgetState();
}

class _VideoGridWidgetState extends State<VideoGridWidget> {
  final _visibilityKey = UniqueKey();
  bool _isAutoPlayEnabled = false;
  VideoPlayerController? _currentController;
  BaseVideoItem? _playingVideo;

  @override
  void dispose() {
    _cleanupController();
    super.dispose();
  }

  Future<void> _cleanupController() async {
    if (_playingVideo != null) {
      await widget.controllerPool.releaseController(_playingVideo!.id);
      _playingVideo = null;
      _currentController = null;
      if (mounted) setState(() {});
    }
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    final visiblePercentage = info.visibleFraction * 100;
    
    // Auto-play when visibility is >= 70%
    if (visiblePercentage >= 70) {
      if (!_isAutoPlayEnabled) {
        _isAutoPlayEnabled = true;
        _startAutoPlay();
      }
    } else {
      // Pause/Stop when visibility drops
      if (_isAutoPlayEnabled) {
        _isAutoPlayEnabled = false;
        _stopAutoPlay();
      }
    }
  }

  Future<void> _startAutoPlay() async {
    if (widget.videos.isEmpty) return;

    final firstVideo = widget.videos.first;
    if (_playingVideo?.id == firstVideo.id && _currentController != null) {
      // Already playing correct video
      if (!_currentController!.value.isPlaying) {
        await _currentController!.play();
      }
      return;
    }

    // Cleanup previous if any
    await _cleanupController();

    // Setup new video
    _playingVideo = firstVideo;
    
    // Acquire controller
    final controller = await widget.controllerPool.acquireController(firstVideo);
    
    if (!mounted || _playingVideo?.id != firstVideo.id) {
       // Setup changed while awaiting
       if (controller != null) {
         await widget.controllerPool.releaseController(firstVideo.id);
       }
       return;
    }

    if (controller != null) {
      _currentController = controller;
      
      // Mute for preview
      await controller.setVolume(0.0);
      
      // Setup looping logic manually to ensure reset to start
      await controller.setLooping(false); // We handle loop manually for specific behavior
      controller.addListener(_videoListener);
      
      await controller.play();
      setState(() {});
    }
  }

  void _videoListener() {
    final c = _currentController;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.position >= c.value.duration) {
      // Video ended, replay from start
      c.seekTo(Duration.zero);
      c.play();
    }
  }

  Future<void> _stopAutoPlay() async {
    final c = _currentController;
    if (c != null && c.value.isPlaying) {
      await c.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibilityChanged,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        physics: const NeverScrollableScrollPhysics(), // Assuming inside a ScrollView
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7, // Aspect ratio from design
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: widget.videos.length,
        itemBuilder: (context, index) {
          final video = widget.videos[index];
          final isFirstItem = index == 0;
          
          return GestureDetector(
            onTap: () => widget.onVideoTap(video),
            child: _buildGridItem(video, isFirstItem),
          );
        },
      ),
    );
  }

  Widget _buildGridItem(BaseVideoItem video, bool isFirstItem) {
    final isPlayingThis = isFirstItem && _isAutoPlayEnabled && _currentController != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail / Cover
          if (!isPlayingThis)
            Container(
              color: Colors.grey[300],
              child: video.extras != null && video.extras!.containsKey('thumbnail') 
                  ? Image.network(
                      video.extras!['thumbnail'] as String,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    )
                  : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)),
            ),

          // Player Surface if playing
          if (isPlayingThis)
            VideoPlayerSurface(
              videoId: video.id,
              controller: _currentController,
              overlay: const SizedBox.shrink(),
              // Optimize: Don't show complex loading/error UI for preview grid
              loadingBuilder: (_) => Container(color: Colors.grey[300]), 
            ),

          // Play Icon Overlay (always show for non-playing, or play icon design)
          if (!isPlayingThis)
             Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            
          // Text Overlay
           Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.extras?['title'] as String? ?? 'Video Title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.extras?['subtitle'] as String? ?? 'Subtitle',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
