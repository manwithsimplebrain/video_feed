import 'package:flutter/material.dart';
import 'package:tiktok/main_screen.dart';
import 'package:tiktok/video_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize video proxy cache (timeout 5s, fallback to direct if fail)
  await VideoCacheService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Feed Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MainScreen(),
    );
  }
}
