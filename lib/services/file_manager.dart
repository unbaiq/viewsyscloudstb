import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/media_item.dart';

class FileManager {
  static final FileManager instance = FileManager._init();
  FileManager._init();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<Directory> get _mediaDirectory async {
    final path = await _localPath;
    final dir = Directory(p.join(path, 'media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Downloads a file from the remote URL and saves it to local disk storage using Dio.
  /// On Web, it bypasses downloading and returns the original URL.
  Future<String?> downloadFile(
    String url,
    int itemId, {
    String? itemType,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      return url; // Direct URL streaming fallback on Web
    }

    try {
      final dir = await _mediaDirectory;
      final uri = Uri.parse(url);
      
      // Handle file extension or default to custom binary format suffix
      String extension = p.extension(uri.path);
      if (extension.isEmpty) {
        if (itemType != null) {
          extension = itemType == 'video' ? '.mp4' : '.jpeg';
        } else {
          // Infer from typical media types or default to generic extension
          extension = url.contains('.mp4') ? '.mp4' : '.jpeg';
        }
      }
      
      final localFileName = 'media_$itemId$extension';
      final localFilePath = p.join(dir.path, localFileName);
      final file = File(localFilePath);

      // Return path if file is already fully downloaded and not empty (e.g. from failed downloads)
      if (await file.exists() && await file.length() > 0) {
        print('Media file ID $itemId already exists locally at: $localFilePath');
        if (onProgress != null) onProgress(1.0);
        return localFilePath;
      }

      print('Downloading media file ID $itemId from URL: $url via Dio...');
      final dio = Dio();
      final response = await dio.download(
        url,
        localFilePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      if (response.statusCode == 200) {
        print('Successfully downloaded and stored local media file: $localFilePath');
        return localFilePath;
      } else {
        print('Failed to download media file: ID $itemId, HTTP Status Code: ${response.statusCode}');
      }
    } catch (e) {
      // Log error internally and return null to fallback to network streaming if needed
      print('Media download error for ID $itemId: $e');
    }
    return null;
  }

  /// Deletes local media files that are no longer referenced in the active playlist.
  Future<void> cleanUnusedFiles(List<MediaItem> activeItems) async {
    if (kIsWeb) return;

    try {
      final dir = await _mediaDirectory;
      final localFiles = dir.listSync();

      // Gather names of files that should remain in cache
      final Set<String> expectedFileNames = {};
      for (final item in activeItems) {
        if (item.localPath != null) {
          expectedFileNames.add(p.basename(item.localPath!));
        }
      }

      // Sweep media folder and delete unreferenced assets
      for (final entity in localFiles) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (!expectedFileNames.contains(name)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      print('Media cleanup error: $e');
    }
  }

  /// Helper to clear all media files in the folder (e.g. on unlinking).
  Future<void> clearAllCachedMedia() async {
    if (kIsWeb) return;

    try {
      final dir = await _mediaDirectory;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      print('Clear cached media error: $e');
    }
  }
}
