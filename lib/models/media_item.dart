import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class MediaItem {
  final int id;
  final String url;
  final String type; // 'image' or 'video'
  final int duration; // in seconds
  final int order;
  final String? localPath; // For cached offline storage
  final ScheduleConfig? schedule;
  final bool? isLandscape; // For dynamic rotation caching

  MediaItem({
    required this.id,
    required this.url,
    required this.type,
    required this.duration,
    required this.order,
    this.localPath,
    this.schedule,
    this.isLandscape,
  });

  MediaItem copyWith({
    int? id,
    String? url,
    String? type,
    int? duration,
    int? order,
    String? localPath,
    ScheduleConfig? schedule,
    bool? isLandscape,
  }) {
    return MediaItem(
      id: id ?? this.id,
      url: url ?? this.url,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      order: order ?? this.order,
      localPath: localPath ?? this.localPath,
      schedule: schedule ?? this.schedule,
      isLandscape: isLandscape ?? this.isLandscape,
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    String url = json['url'] as String? ?? '';
    if (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://')) {
      final baseUrl = 'https://viewsys.co.in';
      final cleanUrl = url.startsWith('/') ? url : '/$url';
      url = '$baseUrl$cleanUrl';
    }

    final parsedId = int.tryParse(json['id']?.toString() ?? '') ?? 0;
    final type = json['type']?.toString() ?? 'image';
    int parsedDuration = int.tryParse(json['duration']?.toString() ?? '') ?? 10;
    if (type == 'image') {
      parsedDuration = 10;
    }
    final orderStr = json['order']?.toString() ?? json['sort_order']?.toString() ?? '';
    final parsedOrder = int.tryParse(orderStr) ?? 0;

    return MediaItem(
      id: parsedId,
      url: url,
      type: type,
      duration: parsedDuration,
      order: parsedOrder,
      localPath: json['local_path'] as String?,
      schedule: json['schedule'] != null
          ? ScheduleConfig.fromJson(json['schedule'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'type': type,
      'duration': duration,
      'order': order,
      'local_path': localPath,
      'schedule': schedule?.toJson(),
    };
  }

  /// Checks if the media file is downloaded and cached locally on disk.
  bool isLocallyAvailable() {
    if (kIsWeb) return true;
    if (localPath == null || localPath!.isEmpty) return false;
    final file = File(localPath!);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Determines if this media item should be displayed right now based on its schedule and connectivity.
  bool isValidNow(DateTime now, {bool isOnline = true}) {
    // If offline, the item must be locally cached to be displayed
    if (!isOnline && !isLocallyAvailable()) {
      return false;
    }

    final sched = schedule;
    if (sched == null) return true; // No schedule implies persistent fallback execution

    // Check date-time range boundaries
    if (sched.startDatetime != null && now.isBefore(sched.startDatetime!)) {
      return false;
    }
    if (sched.endDatetime != null && now.isAfter(sched.endDatetime!)) {
      return false;
    }

    // Check specific days of the week restriction (1 = Monday, 7 = Sunday)
    if (sched.daysOfWeek != null && sched.daysOfWeek!.isNotEmpty) {
      if (!sched.daysOfWeek!.contains(now.weekday)) {
        return false;
      }
    }

    return true;
  }
}

class ScheduleConfig {
  final DateTime? startDatetime;
  final DateTime? endDatetime;
  final List<int>? daysOfWeek;
  final String type; // e.g., 'broadcast'
  final int priority;

  ScheduleConfig({
    this.startDatetime,
    this.endDatetime,
    this.daysOfWeek,
    required this.type,
    required this.priority,
  });

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    DateTime? start;
    if (json['start_datetime'] != null) {
      start = DateTime.tryParse(json['start_datetime'] as String);
    }
    DateTime? end;
    if (json['end_datetime'] != null) {
      end = DateTime.tryParse(json['end_datetime'] as String);
    }

    List<int>? days;
    if (json['days_of_week'] != null) {
      try {
        if (json['days_of_week'] is List) {
          days = (json['days_of_week'] as List<dynamic>)
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList();
        }
      } catch (e) {
        print('Error parsing days_of_week in ScheduleConfig: $e');
      }
    }

    final parsedPriority = int.tryParse(json['priority']?.toString() ?? '') ?? 1;

    return ScheduleConfig(
      startDatetime: start,
      endDatetime: end,
      daysOfWeek: days,
      type: json['type'] as String? ?? 'broadcast',
      priority: parsedPriority,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_datetime': startDatetime?.toIso8601String(),
      'end_datetime': endDatetime?.toIso8601String(),
      'days_of_week': daysOfWeek,
      'type': type,
      'priority': priority,
    };
  }
}
