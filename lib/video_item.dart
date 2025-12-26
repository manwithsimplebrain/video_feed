class BaseVideoItem {
  const BaseVideoItem({
    required this.id,
    required this.videoUrl,
    this.extras,
  });

  final String id;
  final String videoUrl;
  final Map<String, Object?>? extras;
}