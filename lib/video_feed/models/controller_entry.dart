import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Wrapper for VideoPlayerController with LRU metadata.
class ControllerEntry {
  ControllerEntry({
    required this.videoId,
    required this.controller,
    required this.createdAt,
  }) : lastAccessedAt = createdAt;

  /// Unique identifier for the video.
  final String videoId;

  /// The video player controller.
  final VideoPlayerController controller;

  /// When this entry was created.
  final DateTime createdAt;

  /// When this entry was last accessed (for LRU eviction).
  DateTime lastAccessedAt;

  /// Whether the controller has been initialized.
  bool get isInitialized => controller.value.isInitialized;

  /// Whether the controller has an error.
  bool get hasError => controller.value.hasError;

  /// Whether the video is currently playing.
  bool get isPlaying => controller.value.isPlaying;

  /// Mark this entry as recently used.
  void touch() {
    lastAccessedAt = DateTime.now();
  }

  /// Dispose the controller and clean up resources.
  Future<void> dispose() async {
    try {
      if (controller.value.isInitialized) {
        await controller.pause();
      }
      await controller.dispose();
    } catch (e) {
      debugPrint('ControllerEntry: Error disposing $videoId: $e');
    }
  }
}
