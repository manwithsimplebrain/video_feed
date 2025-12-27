import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tiktok/video_item.dart';
import 'package:video_player/video_player.dart';

import '../core/video_cache_service.dart';
import '../core/video_feed_config.dart';
import '../models/controller_entry.dart';

/// Manages a pool of video controllers with LRU eviction.
class ControllerPoolService {
  ControllerPoolService({
    required this.config,
    required this.cacheService,
  });

  final VideoFeedConfig config;
  final VideoCacheService cacheService;

  /// Active controllers indexed by video ID.
  final Map<String, ControllerEntry> _pool = {};

  /// IDs currently being initialized (prevent duplicate init).
  final Set<String> _initializing = {};

  /// IDs currently being disposed (prevent race conditions).
  final Set<String> _disposing = {};

  /// Stream controller for notifying when controllers become ready.
  final _onControllerReady = StreamController<String>.broadcast();

  /// Stream controller for notifying when controllers are disposed.
  final _onControllerDisposed = StreamController<String>.broadcast();

  /// Stream of video IDs when their controllers become ready.
  Stream<String> get onControllerReady => _onControllerReady.stream;

  /// Stream of video IDs when their controllers are disposed.
  Stream<String> get onControllerDisposed => _onControllerDisposed.stream;

  /// Get controller if available and initialized.
  VideoPlayerController? getController(String videoId) {
    final entry = _pool[videoId];
    if (entry != null && entry.isInitialized && !entry.hasError) {
      entry.touch();
      return entry.controller;
    }
    return null;
  }

  /// Check if controller exists (initialized or not).
  bool hasController(String videoId) => _pool.containsKey(videoId);

  /// Check if controller is ready to play.
  bool isReady(String videoId) {
    final entry = _pool[videoId];
    return entry != null && entry.isInitialized && !entry.hasError;
  }

  /// Acquire or create a controller for a video.
  /// Returns null if initialization fails or times out.
  Future<VideoPlayerController?> acquireController(BaseVideoItem video) async {
    // Return existing if available
    if (_pool.containsKey(video.id)) {
      final entry = _pool[video.id]!;
      entry.touch();
      if (entry.isInitialized) return entry.controller;
      return null;
    }

    // Prevent duplicate initialization
    if (_initializing.contains(video.id)) return null;

    _initializing.add(video.id);

    try {
      // Enforce pool size before creating new controller
      await _enforcePoolLimit(excluding: video.id);

      // Create controller using proxied URL
      final proxyUrl = cacheService.getProxiedUrl(video.videoUrl);
      final controller = VideoPlayerController.networkUrl(proxyUrl);

      // Initialize with timeout
      await controller.initialize().timeout(
        Duration(milliseconds: config.controllerInitTimeoutMs),
        onTimeout: () {
          throw TimeoutException('Controller init timeout for ${video.id}');
        },
      );

      await controller.setLooping(true);

      // Create entry and add to pool
      final entry = ControllerEntry(
        videoId: video.id,
        controller: controller,
        createdAt: DateTime.now(),
      );

      _pool[video.id] = entry;
      _onControllerReady.add(video.id);

      return controller;
    } catch (e) {
      debugPrint('ControllerPool: Failed to acquire ${video.id}: $e');
      return null;
    } finally {
      _initializing.remove(video.id);
    }
  }

  /// Release a specific controller.
  Future<void> releaseController(String videoId) async {
    if (_disposing.contains(videoId)) return;

    final entry = _pool[videoId];
    if (entry == null) return;

    _disposing.add(videoId);

    try {
      _pool.remove(videoId);
      _onControllerDisposed.add(videoId);
      await entry.dispose();
    } catch (e) {
      debugPrint('ControllerPool: Error disposing $videoId: $e');
    } finally {
      _disposing.remove(videoId);
    }
  }

  /// Enforce pool size limit using LRU eviction.
  Future<void> _enforcePoolLimit({String? excluding}) async {
    while (_pool.length >= config.controllerPoolSize) {
      ControllerEntry? lruEntry;
      String? lruId;

      for (final entry in _pool.entries) {
        if (entry.key == excluding) continue;
        if (_disposing.contains(entry.key)) continue;

        if (lruEntry == null ||
            entry.value.lastAccessedAt.isBefore(lruEntry.lastAccessedAt)) {
          lruEntry = entry.value;
          lruId = entry.key;
        }
      }

      if (lruId != null) {
        await releaseController(lruId);
      } else {
        break;
      }
    }
  }

  /// Release all controllers not in the given set of IDs.
  Future<void> releaseControllersExcept(Set<String> keepIds) async {
    final toRelease =
        _pool.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in toRelease) {
      await releaseController(id);
    }
  }

  /// Pause all controllers.
  Future<void> pauseAll() async {
    for (final entry in _pool.values) {
      try {
        if (entry.isInitialized && entry.isPlaying) {
          await entry.controller.pause();
        }
      } catch (e) {
        debugPrint('ControllerPool: Error pausing: $e');
      }
    }
  }

  /// Play specific controller.
  Future<void> play(String videoId) async {
    final entry = _pool[videoId];
    if (entry != null && entry.isInitialized && !entry.isPlaying) {
      try {
        await entry.controller.play();
      } catch (e) {
        debugPrint('ControllerPool: Error playing $videoId: $e');
      }
    }
  }

  /// Dispose all and clean up.
  Future<void> dispose() async {
    await _onControllerReady.close();
    await _onControllerDisposed.close();

    final ids = List<String>.from(_pool.keys);
    for (final id in ids) {
      await releaseController(id);
    }
    _pool.clear();
  }

  /// Get pool statistics for debugging.
  Map<String, dynamic> getStats() {
    return {
      'poolSize': _pool.length,
      'maxSize': config.controllerPoolSize,
      'initializing': _initializing.length,
      'disposing': _disposing.length,
      'entries': _pool.entries
          .map((e) => {
                'id': e.key,
                'initialized': e.value.isInitialized,
                'lastAccessed': e.value.lastAccessedAt.toIso8601String(),
              })
          .toList(),
    };
  }
}
