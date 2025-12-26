/// Detects rapid scrolling in the video feed.
class FastScrollDetector {
  FastScrollDetector({
    this.threshold = 2,
  });

  /// Pages skipped to trigger fast scroll detection.
  final int threshold;

  int? _lastPage;
  int _consecutiveFastScrolls = 0;

  /// Detect if this is a fast scroll.
  /// Returns true if user scrolled more than [threshold] pages.
  bool detect(int fromPage, int toPage) {
    final delta = (toPage - fromPage).abs();
    final isFast = delta > threshold;

    // Track consecutive fast scrolls for adaptive behavior
    if (isFast) {
      _consecutiveFastScrolls++;
    } else {
      _consecutiveFastScrolls = 0;
    }

    _lastPage = toPage;

    return isFast;
  }

  /// Check if user is in "browsing mode" (consecutive fast scrolls).
  bool get isBrowsingMode => _consecutiveFastScrolls >= 2;

  /// Get the last detected page.
  int? get lastPage => _lastPage;

  /// Reset the detector.
  void reset() {
    _lastPage = null;
    _consecutiveFastScrolls = 0;
  }
}
