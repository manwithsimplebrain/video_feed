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

- **main.dart** - App entry point with `DemoVideoFeedView` demonstrating the video feed with pagination (loads 6 initial videos, 3 per batch on scroll)

- **tiktok_video.dart** - Legacy video feed implementation:
  - LRU cache for `VideoPlayerController` instances (configurable, default 3)
  - Background video file caching via `flutter_cache_manager`
  - Sliding window controller management (current page +/- 1)
  - Fast scroll detection with aggressive cleanup
  - App lifecycle handling via `WidgetsBindingObserver`

- **video_optimize.dart** - Optimized video player widget with buffering state management and tap-to-play/pause

- **video_item.dart** - Abstract `BaseVideoItem` class (requires `id` and `videoUrl` properties)

### New Modular Architecture (`lib/video_feed/`)

The refactored video feed system uses a service-based architecture with clear separation of concerns:

**Core Services:**
- **core/video_cache_service.dart** - Wraps `flutter_video_caching` for video proxying and precaching
- **services/controller_pool_service.dart** - Manages LRU pool of `VideoPlayerController` instances with timeout handling
- **services/preload_manager.dart** - Coordinates preloading of videos ahead/behind current position
- **utils/fast_scroll_detector.dart** - Detects rapid scrolling to trigger aggressive cleanup

**Widgets:**
- **widgets/video_feed_view.dart** - Main vertical feed widget with pagination support
- **widgets/video_player_surface.dart** - Video rendering surface with play/pause, buffering states, and layout modes
- **widgets/video_grid_widget.dart** - Grid view with auto-play for first visible item using `VisibilityDetector`

**Configuration:**
- **core/video_feed_config.dart** - Centralized config for pool size, preload counts, cache limits, timeouts

**Demo implementations:**
- **demo/basic_video_item.dart** - Simple implementation of `BaseVideoItem`
- **demo/preview_video_item.dart** - Extended video item with thumbnail URL
- **demo/video_grid_demo.dart** - Example grid view implementation

### Key Initialization Pattern

The app **must** initialize `VideoCacheService` before `runApp()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VideoCacheService.initialize(const VideoFeedConfig());
  runApp(const MyApp());
}
```

### Memory Management Strategy

- **Controller Pool**: LRU eviction keeps only `controllerPoolSize` (default 5) controllers in memory
- **Preloading**: Configurable ahead/behind counts (`preloadAhead: 5`, `preloadBehind: 1`)
- **Fast Scroll**: When user skips >2 pages (configurable via `fastScrollThreshold`), all controllers except target are disposed
- **Lifecycle**: Controllers paused when app backgrounded, current video replayed on resume
- **Timeout Handling**: Controller initialization times out after `controllerInitTimeoutMs` (default 5000ms)

### Key Patterns

- **RepaintBoundary**: Wraps video items to isolate repaints and improve scroll performance
- **Post-frame callbacks**: Used to avoid `setState` during build phase
- **Stream subscriptions**: `ControllerPoolService` emits disposal events (`onControllerDisposed`) to trigger UI updates
- **Visibility detection**: Grid widget uses `visibility_detector` for auto-play of first visible item
- **Pagination**: `onNeedMore` callback triggered when within `loadMoreThreshold` (default 3) videos from the end

### Dependencies

- `video_player` - Video playback
- `preload_page_view` - Vertical page scrolling with preloading
- `flutter_video_caching` - Local proxy caching for video files (new architecture)
- `flutter_cache_manager` - Background video file caching (legacy architecture)
- `visibility_detector` - Track widget visibility for grid auto-play
