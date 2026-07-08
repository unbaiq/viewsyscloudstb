import 'dart:typed_data';
import 'package:screenshot/screenshot.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../widgets/video_player_widget.dart';

class ScreenshotService {
  /// Global screenshot controller to capture frame buffers wrapped in the Screenshot widget.
  static final ScreenshotController screenshotController = ScreenshotController();

  /// Captures the current player screen repaint boundary and sends PNG bytes to `/screenshot`.
  static Future<void> captureAndUpload(String screenId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final Uint8List? baseImageBytes = await screenshotController.capture(pixelRatio: 1.0);
      if (baseImageBytes == null) {
        print('Screenshot capture failed: baseImageBytes is null.');
        return;
      }

      Map<int, ui.Image> videoFrames = {};
      try {
        videoFrames = await VideoFrameRegistry.instance.captureAllFrames();
      } catch (e) {
        print('Error capturing video frames: $e');
      }

      if (videoFrames.isEmpty) {
        await _upload(screenId, baseImageBytes);
        return;
      }

      // We have video frames to composite
      final ui.Codec baseCodec = await ui.instantiateImageCodec(baseImageBytes);
      final ui.FrameInfo baseFrameInfo = await baseCodec.getNextFrame();
      final ui.Image baseImage = baseFrameInfo.image;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Draw the base UI image
      canvas.drawImage(baseImage, Offset.zero, Paint());

      // Composite each active video frame
      for (final entry in videoFrames.entries) {
        final int itemId = entry.key;
        final ui.Image frameImage = entry.value;

        final GlobalKey? key = VideoFrameRegistry.instance.keyFor(itemId);
        if (key != null && key.currentContext != null) {
          final RenderBox? box = key.currentContext!.findRenderObject() as RenderBox?;
          if (box != null) {
            final Offset position = box.localToGlobal(Offset.zero);
            final Size size = box.size;

            final Rect videoRect = Rect.fromLTWH(
              position.dx * 1.0,
              position.dy * 1.0,
              size.width * 1.0,
              size.height * 1.0,
            );

            final Rect srcRect = Rect.fromLTWH(0, 0, frameImage.width.toDouble(), frameImage.height.toDouble());
            canvas.drawImageRect(frameImage, srcRect, videoRect, Paint());
            frameImage.dispose();
          }
        }
      }

      try {
        final ui.Picture picture = recorder.endRecording();
        final ui.Image compositeImage = await picture.toImage(baseImage.width, baseImage.height);
        final ByteData? byteData = await compositeImage.toByteData(format: ui.ImageByteFormat.png);
        baseImage.dispose();
        compositeImage.dispose();

        if (byteData != null) {
          await _upload(screenId, byteData.buffer.asUint8List());
        } else {
          await _upload(screenId, baseImageBytes);
        }
      } catch (e) {
        print('Compositing failed: $e');
        await _upload(screenId, baseImageBytes);
      }
    } catch (e) {
      print('Screenshot capture exception: $e');
    }
  }

  /// Sends the captured binary PNG bytes using multipart/form-data via http.
  static Future<bool> _upload(String screenId, Uint8List bytes) async {
    try {
      final uri = Uri.parse('https://viewsys.co.in/api/player/screenshot');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';
      request.fields['screen_id'] = screenId;
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'screen_${screenId}_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        print('Screenshot uploaded successfully via http: $responseBody');
        return true;
      } else {
        print('Screenshot upload failed with status: ${response.statusCode}, Data: $responseBody');
      }
    } catch (e) {
      print('Screenshot upload exception via http: $e');
    }
    return false;
  }
}
