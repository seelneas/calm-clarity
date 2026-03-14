import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_service.dart';
import 'preferences_service.dart';

class MediaService {
  static String _detectContentType(String filename, {required String mediaType}) {
    final lower = filename.toLowerCase();

    if (mediaType == 'profile') {
      if (lower.endsWith('.png')) return 'image/png';
      if (lower.endsWith('.webp')) return 'image/webp';
      return 'image/jpeg';
    }

    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return 'audio/mp4';
  }

  static Map<String, dynamic> _parseResponse({
    required int statusCode,
    required String body,
    required String fallbackMessage,
  }) {
    dynamic payload;
    try {
      payload = jsonDecode(body);
    } catch (_) {
      payload = null;
    }

    if (statusCode >= 200 && statusCode < 300 && payload is Map<String, dynamic>) {
      return {
        'success': true,
        ...payload,
      };
    }

    final message = payload is Map<String, dynamic>
        ? (payload['detail'] ?? payload['message'] ?? fallbackMessage)
        : fallbackMessage;
    return {
      'success': false,
      'message': message.toString(),
      'status_code': statusCode,
    };
  }

  static Future<Map<String, dynamic>> uploadProfilePhoto(XFile imageFile) async {
    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final filename = imageFile.name.trim().isEmpty
          ? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : imageFile.name;
      final bytes = await imageFile.readAsBytes();
      final contentType = _detectContentType(filename, mediaType: 'profile');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/media/upload'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['media_type'] = 'profile'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: _httpMediaType(contentType),
          ),
        );

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      return _parseResponse(
        statusCode: streamed.statusCode,
        body: body,
        fallbackMessage: 'Profile photo upload failed',
      );
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadVoiceRecordingFromPath(String filePath) async {
    if (kIsWeb) {
      return {
        'success': false,
        'message': 'Voice file upload from local path is not supported on web.',
      };
    }

    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      final filename = filePath.split('/').last.trim().isEmpty
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'
          : filePath.split('/').last;
      final contentType = _detectContentType(filename, mediaType: 'voice');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/media/upload'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['media_type'] = 'voice'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: filename,
            contentType: _httpMediaType(contentType),
          ),
        );

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      return _parseResponse(
        statusCode: streamed.statusCode,
        body: body,
        fallbackMessage: 'Voice recording upload failed',
      );
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadVoiceRecordingBytes(
    Uint8List bytes, {
    String filename = 'voice_recording.webm',
    String? contentType,
  }) async {
    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'message': 'Sign in required'};
      }

      if (bytes.isEmpty) {
        return {'success': false, 'message': 'Voice recording is empty'};
      }

      final safeFilename = filename.trim().isEmpty
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.webm'
          : filename.trim();
      final resolvedContentType =
          (contentType ?? _detectContentType(safeFilename, mediaType: 'voice'))
              .trim()
              .toLowerCase();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/media/upload'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['media_type'] = 'voice'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: safeFilename,
            contentType: _httpMediaType(resolvedContentType),
          ),
        );

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      return _parseResponse(
        statusCode: streamed.statusCode,
        body: body,
        fallbackMessage: 'Voice recording upload failed',
      );
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static MediaType _httpMediaType(String contentType) {
    final chunks = contentType.split('/');
    if (chunks.length != 2) {
      return MediaType('application', 'octet-stream');
    }
    return MediaType(chunks[0], chunks[1]);
  }

  static Future<String?> refreshMediaUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    
    // Don't refresh data URLs or local paths
    if (trimmed.startsWith('data:') || 
        trimmed.startsWith('blob:') ||
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'))) {
      return trimmed;
    }

    try {
      final token = await PreferencesService.getAuthToken();
      if (token == null || token.isEmpty) return trimmed;

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/media/refresh'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': trimmed}),
      );

      final result = _parseResponse(
        statusCode: response.statusCode,
        body: response.body,
        fallbackMessage: 'URL refresh failed',
      );

      if (result['success'] == true && 
          (result['public_url'] ?? '').toString().trim().isNotEmpty) {
        return (result['public_url'] as String).trim();
      }
    } catch (_) {
      // Fallback to original URL on error
    }
    
    return trimmed;
  }
}
