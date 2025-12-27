import 'package:flutter/material.dart';
import 'package:tiktok/video_feed/core/video_cache_service.dart';
import 'package:tiktok/video_feed/core/video_feed_config.dart';
import 'package:tiktok/video_feed/services/controller_pool_service.dart';
import 'package:tiktok/video_feed/widgets/video_grid_widget.dart';
import 'package:tiktok/video_item.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Setup Config
  const config = VideoFeedConfig();
  
  // 2. Initialize Cache
  await VideoCacheService.initialize(config);

  runApp(const VideoGridDemoApp());
}

class VideoGridDemoApp extends StatelessWidget {
  const VideoGridDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Grid Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const VideoGridDemoPage(),
    );
  }
}

class VideoGridDemoPage extends StatefulWidget {
  const VideoGridDemoPage({super.key});

  @override
  State<VideoGridDemoPage> createState() => _VideoGridDemoPageState();
}

class _VideoGridDemoPageState extends State<VideoGridDemoPage> {
  late final VideoCacheService _cacheService;
  late final ControllerPoolService _poolService;
  
  final List<BaseVideoItem> _videos = [
    const BaseVideoItem(
      id: 'v1',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4',
      extras: {
        'title': 'Big Blazes',
        'subtitle': 'Action',
        'thumbnail': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
      },
    ),
    const BaseVideoItem(
      id: 'v2',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
      extras: {
        'title': 'Escapes',
        'subtitle': 'Adventure',
         'thumbnail': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
      },
    ),
    const BaseVideoItem(
      id: 'v3',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
      extras: {
        'title': 'Joyrides',
        'subtitle': 'Fun',
         'thumbnail': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
      },
    ),
    const BaseVideoItem(
      id: 'v4',
      videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
      extras: {
        'title': 'Meltdowns',
        'subtitle': 'Drama',
         'thumbnail': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
      },
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cacheService = VideoCacheService();
    _poolService = ControllerPoolService(
      config: const VideoFeedConfig(),
      cacheService: _cacheService,
    );
  }

  @override
  void dispose() {
    _poolService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Grid Demo')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 300,
              width: double.infinity,
              color: Colors.grey[200],
              alignment: Alignment.center,
              child: const Text('Scroll Down to see Grid'),
            ),
            
            // The Widget under test
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VideoGridWidget(
                videos: _videos,
                controllerPool: _poolService,
                onVideoTap: (video) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tapped: ${video.id}')),
                  );
                },
              ),
            ),

            Container(
              height: 800,
              width: double.infinity,
              color: Colors.grey[200],
              alignment: Alignment.center,
              child: const Text('Scroll Up to hide Grid'),
            ),
          ],
        ),
      ),
    );
  }
}
