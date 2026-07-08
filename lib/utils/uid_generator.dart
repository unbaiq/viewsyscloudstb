class UidGenerator {
  static String generateUid() {
    final now = DateTime.now();

    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    final seconds = now.second.toString().padLeft(2, '0');

    // get milliseconds (0-999), pad to 3 digits, and take the first 2
    final milliseconds = now.millisecond
        .toString()
        .padLeft(3, '0')
        .substring(0, 2);

    // Total: 4 + 2 + 2 + 2 + 2 + 2 + 2 = 16 digits
    return '$year$month$day$hours$minutes$seconds$milliseconds';
  }
}
