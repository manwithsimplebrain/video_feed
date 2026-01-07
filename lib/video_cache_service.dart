import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_video_caching/flutter_video_caching.dart';

/// Service wrapper cho flutter_video_caching với lazy caching
/// - Chỉ dùng proxy khi video ĐANG PLAY (không precache trước)
/// - Nếu proxy fail, tự động fallback về direct URL
/// - Giảm lag vì không download trước
class VideoCacheService {
  static VideoCacheService? _instance;
  static VideoCacheService get instance => _instance ??= VideoCacheService._();

  VideoCacheService._();

  bool _isInitialized = false;
  bool _isProxyAvailable = false;

  /// Timeout cho việc initialize proxy (ms)
  static const int _initTimeoutMs = 5000;

  /// Số lần retry khi proxy fail
  int _proxyFailCount = 0;
  static const int _maxProxyFailures = 3;

  /// Cache URL đã convert để không convert lại
  final Map<String, String> _urlCache = {};

  /// Initialize service với timeout
  /// Nếu timeout hoặc fail, service vẫn hoạt động nhưng không dùng proxy
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('VideoCacheService: Initializing proxy...');

      await Future.any([
        _initProxy(),
        Future.delayed(const Duration(milliseconds: _initTimeoutMs), () {
          throw TimeoutException('Proxy init timeout after ${_initTimeoutMs}ms');
        }),
      ]);

      _isProxyAvailable = true;
      _isInitialized = true;
      debugPrint('VideoCacheService: Proxy initialized successfully');
    } catch (e) {
      _isProxyAvailable = false;
      _isInitialized = true;
      debugPrint('VideoCacheService: Proxy init failed ($e), using direct URLs');
    }
  }

  Future<void> _initProxy() async {
    await VideoProxy.init(
      maxMemoryCacheSize: 30,        // 30MB memory cache (giảm từ 50)
      maxStorageCacheSize: 150,      // 150MB disk cache
      segmentSize: 1,                // 1MB per segment (giảm từ 2)
      maxConcurrentDownloads: 2,     // Chỉ 2 concurrent (giảm từ 3)
      logPrint: false,               // Tắt log để giảm overhead
    );
  }

  /// Lấy URL để play video - CHỈ DÙNG KHI VIDEO ĐANG PLAY
  /// Trả về proxy URL nếu available, ngược lại trả về direct URL
  String getPlayUrl(String originalUrl) {
    // Nếu proxy không available hoặc đã fail nhiều, dùng direct URL
    if (!_isProxyAvailable || _proxyFailCount >= _maxProxyFailures) {
      return originalUrl;
    }

    // Check cache trước
    if (_urlCache.containsKey(originalUrl)) {
      return _urlCache[originalUrl]!;
    }

    try {
      final proxyUrl = originalUrl.toLocalUri().toString();
      _urlCache[originalUrl] = proxyUrl;
      _proxyFailCount = 0;
      return proxyUrl;
    } catch (e) {
      _proxyFailCount++;
      debugPrint('VideoCacheService: Proxy URL failed ($e). Failures: $_proxyFailCount');
      return originalUrl;
    }
  }

  /// Check if should use proxy for this video
  /// Dùng để quyết định có dùng proxy hay không
  bool shouldUseProxy() {
    return _isProxyAvailable && _proxyFailCount < _maxProxyFailures;
  }

  /// Remove cache for specific URL (khi dispose controller)
  void removeCacheForUrl(String url) {
    _urlCache.remove(url);

    if (!_isProxyAvailable) return;

    try {
      LruCacheSingleton().removeCacheByUrl(url, singleFile: false);
    } catch (e) {
      // Ignore errors
    }
  }

  /// Clear URL cache (không clear disk cache)
  void clearUrlCache() {
    _urlCache.clear();
  }

  /// Reset proxy state (thử lại sau khi fail)
  void resetProxyState() {
    _proxyFailCount = 0;
    debugPrint('VideoCacheService: Proxy state reset');
  }

  /// Check if proxy is available
  bool get isProxyAvailable => _isProxyAvailable;

  /// Dispose service
  void dispose() {
    _urlCache.clear();
    _isInitialized = false;
    _isProxyAvailable = false;
    _proxyFailCount = 0;
  }
}
