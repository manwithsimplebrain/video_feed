import 'package:flutter/material.dart';
import 'package:tiktok/tiktok_video.dart';
import 'package:tiktok/video_item.dart';

/// Simple implementation of BaseVideoItem
class SimpleVideoItem extends BaseVideoItem {
  const SimpleVideoItem({required super.id, required super.videoUrl});
}

/// Demo screen showing the VideoFeedView with caching.
class DemoVideoFeedView extends StatefulWidget {
  const DemoVideoFeedView({super.key});

  @override
  State<DemoVideoFeedView> createState() => _DemoVideoFeedViewState();
}

class _DemoVideoFeedViewState extends State<DemoVideoFeedView> {
  static final List<SimpleVideoItem> _allSampleVideos = [
    const SimpleVideoItem(
      id: 'v1_short',
      videoUrl:
          'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
    const SimpleVideoItem(
      id: 'v2_short',
      videoUrl:
          'https://vz-cea98c59-23c.b-cdn.net/c309129c-27b6-4e43-8254-62a15c77c5ee/playlist.m3u8?v=1683126052',
    ),
    const SimpleVideoItem(
      id: 'v3_short',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    ),
    const SimpleVideoItem(
      id: 'v4_short',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    ),
    const SimpleVideoItem(
      id: 'v5_fun',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    ),
    const SimpleVideoItem(
      id: 'v6_escapes',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    ),
    const SimpleVideoItem(
      id: 'v7_elephants',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    ),
    const SimpleVideoItem(
      id: 'v8_bullrun',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4',
    ),
    const SimpleVideoItem(
      id: 'v9_sintel',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    ),
    const SimpleVideoItem(
      id: 'v10_tears',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    ),
    const SimpleVideoItem(
      id: 'v11_volcano',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4',
    ),
    const SimpleVideoItem(
      id: 'v12_subaru',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4',
    ),
    const SimpleVideoItem(
      id: 'v13_whatcar',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WhatCarCanYouGetForAGrand.mp4',
    ),
    const SimpleVideoItem(
      id: 'v14_butterfly2',
      videoUrl:
          'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    ),
    const SimpleVideoItem(
      id: 'v15_final',
      videoUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    ),
  ];

  late final List<SimpleVideoItem> _currentVideos = _allSampleVideos.take(6).toList();
  int _loadedCount = 6;
  bool _isLoadingMore = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            VideoFeedView(
              videos: _currentVideos,
              maxControllerCache: 3, // prev + current + next
              preloadAhead: 1,
              overlayBuilder: (context, item) {
                final index = _currentVideos.indexWhere((v) => v.id == item.id);
                return Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Video ${index + 1}/${_currentVideos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${item.id}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap to play/pause. Swipe to scroll.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        if (_isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Loading more...',
                              style:
                                  TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              onNeedMore: () async {
                await Future.delayed(const Duration(milliseconds: 500));

                if (_loadedCount >= _allSampleVideos.length) {
                  return const <BaseVideoItem>[];
                }

                setState(() {
                  _isLoadingMore = true;
                });

                final nextBatch =
                    _allSampleVideos.skip(_loadedCount).take(3).toList();

                _loadedCount += nextBatch.length;

                setState(() {
                  _isLoadingMore = false;
                });

                return nextBatch;
              },
            ),
            // Video count indicator
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentVideos.length}/${_allSampleVideos.length} videos',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
