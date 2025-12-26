# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VideoFeed (package name: "tiktok") is a Flutter application implementing a TikTok-style vertical video feed with efficient video playback, preloading, and memory management.

## Build Commands

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Static analysis
flutter analyze

# Build for platforms
flutter build apk      # Android
flutter build ios      # iOS
flutter build web      # Web
```

## Architecture

### Core Components (`lib/`)

- **main.dart** - App entry point with `DemoTikTokBaseView` demonstrating the video feed with pagination (loads 6 initial videos, 3 per batch on scroll)

- **tiktok_video.dart** - Core video feed implementation (`VideoFeedView`):
  - LRU cache for `VideoPlayerController` instances (configurable, default 3)
  - Background video file caching via `flutter_cache_manager`
  - Sliding window controller management (current page +/- 1)
  - Fast scroll detection with aggressive cleanup
  - App lifecycle handling via `WidgetsBindingObserver`

- **video_optimize.dart** - Optimized video player widget with buffering state management and tap-to-play/pause

- **video_item.dart** - Simple `BaseVideoItem` data model (id, videoUrl, extras)

### Key Patterns

- **Memory management**: Only 3 controllers kept in memory at once; least-recently-used eviction
- **Preloading**: Configurable `preloadAhead` parameter for background file caching
- **Performance**: `RepaintBoundary` widgets, post-frame callbacks to avoid build conflicts
- **Pagination**: `onNeedMore` callback triggered when within 2 videos of the end

### Dependencies

- `video_player` - Video playback
- `preload_page_view` - Vertical page scrolling with preloading
- `flutter_cache_manager` - Background video file caching
