import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../core/opensubtitles_config.dart';
import '../../repository/locale/panel_api_keys.dart';

/// Debug logging for the OpenSubtitles integration (no behavior changes).
class OpenSubtitlesDebugLog {
  OpenSubtitlesDebugLog._();

  static const _name = 'OpenSubtitles';

  static void _log(String message) {
    developer.log(message, name: _name);
  }

  static String _maskKey(String value, {int visible = 8}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '(empty)';
    if (trimmed.length <= visible) {
      return '${trimmed.substring(0, trimmed.length ~/ 2)}...';
    }
    return '${trimmed.substring(0, visible)}...';
  }

  static String _maskToken(String value, {int visible = 20}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '(empty)';
    if (trimmed.length <= visible) return '$trimmed...';
    return '${trimmed.substring(0, visible)}...';
  }

  static Map<String, dynamic> redactHeaders(Map<String, String> headers) {
    final copy = <String, dynamic>{};
    headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'api-key') {
        copy[key] = _maskKey(value);
      } else if (lower == 'authorization') {
        copy[key] = _maskToken(value);
      } else {
        copy[key] = value;
      }
    });
    return copy;
  }

  static String _bodyToString(dynamic data) {
    if (data == null) return '(null)';
    if (data is Map || data is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(data);
      } catch (_) {
        return data.toString();
      }
    }
    if (data is String) return data;
    return data.toString();
  }

  // ====================== 1) SETTINGS ======================

  static void logSettings() {
    final apiKey = effectiveOpensubtitlesApiKey;
    final username = effectiveOpensubtitlesUsername;
    final password = effectiveOpensubtitlesPassword;

    _log('═══ SETTINGS ═══');
    _log('Base URL: $kOpensubtitlesBaseUrl');
    _log(
      'Api Key present: ${apiKey.isNotEmpty} (${apiKey.isEmpty ? 'empty' : _maskKey(apiKey)})',
    );
    _log('Username: ${username.isEmpty ? '(empty)' : username}');
    _log('Password present: ${password.isNotEmpty}');
  }

  // ====================== 2) LOGIN ======================

  static void logLoginRequest({
    required String url,
    required Map<String, String> headers,
    required String username,
  }) {
    _log('═══ LOGIN REQUEST ═══');
    _log('URL: $url');
    _log('Headers: ${jsonEncode(redactHeaders(headers))}');
    _log('Body: ${jsonEncode({'username': username, 'password': '***'})}');
  }

  static void logLoginSuccess({
    required int? statusCode,
    required dynamic responseBody,
    String? token,
  }) {
    _log('═══ LOGIN SUCCESS ═══');
    _log('Status Code: $statusCode');
    _log('Response Body:\n${_bodyToString(responseBody)}');
    if (token != null && token.isNotEmpty) {
      _log('Token (first 20 chars): ${_maskToken(token)}');
    } else {
      _log('Token: NOT_RECEIVED');
    }
  }

  static void logLoginSkipped({required String reason}) {
    _log('═══ LOGIN SKIPPED ═══');
    _log('Reason: $reason');
  }

  static void logLoginFailure({
    int? statusCode,
    dynamic responseBody,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log('═══ LOGIN FAILED ═══');
    _log('Status Code: ${statusCode ?? 'N/A'}');
    _log('Response Body:\n${_bodyToString(responseBody)}');
    if (error != null) {
      _log('Error: $error');
      if (error is DioException) {
        logDioException(error, stackTrace);
      }
    }
    if (stackTrace != null) {
      _log('StackTrace:\n$stackTrace');
    }
  }

  // ====================== 3) TMDB ======================

  static void logTmdbContext({
    required String? tmdbId,
    String? imdbId,
    String? contentKey,
    String? title,
    bool? isSeries,
    int? year,
    String? searchBy,
  }) {
    _log('═══ TMDB CONTEXT ═══');
    _log('content_key: ${contentKey ?? 'N/A'}');
    _log('title: ${title ?? 'N/A'}');
    _log('is_series: ${isSeries ?? 'N/A'}');
    _log('year: ${year ?? 'N/A'}');
    _log('search_by: ${searchBy ?? 'N/A'}');
    if (tmdbId != null && tmdbId.trim().isNotEmpty && tmdbId != '0') {
      _log('tmdb_id: $tmdbId');
    } else {
      _log('tmdb_id: NOT_FOUND (missing or empty in IPTV metadata / cache)');
    }
    if (imdbId != null && imdbId.trim().isNotEmpty) {
      _log('imdb_id: $imdbId');
    } else {
      _log('imdb_id: NOT_AVAILABLE (not provided by IPTV metadata)');
    }
  }

  static void logTmdbResolveResult({
    required String? resolvedId,
    required String reason,
  }) {
    _log('═══ TMDB RESOLVE RESULT ═══');
    if (resolvedId != null && resolvedId.isNotEmpty) {
      _log('Resolved tmdb_id: $resolvedId');
    } else {
      _log('Resolved tmdb_id: NOT_FOUND');
    }
    _log('Reason: $reason');
  }

  // ====================== 4) SEARCH ======================

  /// Prints full request details before each cascade search attempt.
  static void logSearchAttempt({
    required String url,
    required Map<String, dynamic> queryParameters,
    required Map<String, String> headers,
    String? originalImdbId,
    String? normalizedImdbId,
    String? imdbParamKey,
    String? imdbParamValue,
    String? originalTmdbId,
    String? tmdbParamKey,
    String? tmdbParamValue,
    String? originalTitle,
    String? sanitizedTitle,
    String? queryTitleSent,
    int? yearSent,
    String? originalFileName,
    String? sanitizedFileName,
    String? queryFileNameSent,
  }) {
    _log('═══ SEARCH ATTEMPT ═══');
    _log('URL: $url');
    _log('Query Parameters: ${jsonEncode(queryParameters)}');
    _log('Headers: ${jsonEncode(redactHeaders(headers))}');

    if (originalImdbId != null ||
        normalizedImdbId != null ||
        imdbParamKey != null) {
      _log('Original IMDb: ${originalImdbId ?? '(none)'}');
      _log('Normalized IMDb: ${normalizedImdbId ?? '(none)'}');
      _log(
        'Query ${imdbParamKey ?? 'imdb_id'} sent to OpenSubtitles: ${imdbParamValue ?? '(none)'}',
      );
    }

    if (originalTmdbId != null || tmdbParamKey != null) {
      _log('Original TMDB: ${originalTmdbId ?? '(none)'}');
      _log(
        'Query ${tmdbParamKey ?? 'tmdb_id'} sent to OpenSubtitles: ${tmdbParamValue ?? '(none)'}',
      );
    }

    if (originalTitle != null ||
        sanitizedTitle != null ||
        queryTitleSent != null) {
      _log('Original title: ${originalTitle ?? '(none)'}');
      _log('Sanitized title: ${sanitizedTitle ?? '(none)'}');
      _log('Query title sent: ${queryTitleSent ?? '(none)'}');
      if (yearSent != null) {
        _log('Year sent: $yearSent');
      }
    }

    if (originalFileName != null ||
        sanitizedFileName != null ||
        queryFileNameSent != null) {
      _log('Original file name: ${originalFileName ?? '(none)'}');
      _log('Sanitized file name: ${sanitizedFileName ?? '(none)'}');
      _log('Query file name sent: ${queryFileNameSent ?? '(none)'}');
    }
  }

  // ====================== 5) DOWNLOAD ======================

  static void logDownloadRequest({required int fileId}) {
    _log('═══ DOWNLOAD REQUEST ═══');
    _log('file_id: $fileId');
  }

  static void logDownloadResponse({
    required String? downloadUrl,
    required int? statusCode,
    required dynamic responseBody,
  }) {
    _log('═══ DOWNLOAD RESPONSE ═══');
    _log('Download URL: ${downloadUrl ?? 'N/A'}');
    _log('Status Code: $statusCode');
    _log('Response Body:\n${_bodyToString(responseBody)}');
  }

  static void logDownloadFileFetch({
    required String url,
    required int? statusCode,
    int? byteCount,
  }) {
    _log('═══ DOWNLOAD FILE FETCH ═══');
    _log('URL: $url');
    _log('Status Code: $statusCode');
    _log('Bytes received: ${byteCount ?? 0}');
  }

  // ====================== 6) ERRORS ======================

  static void logDioException(DioException error, [StackTrace? stackTrace]) {
    _log('═══ DIO EXCEPTION ═══');
    _log('Exception Type: ${error.type}');
    _log('Message: ${error.message}');
    _log('Request URL: ${error.requestOptions.uri}');
    _log(
      'Request Headers: ${jsonEncode(redactHeaders(Map<String, String>.from(error.requestOptions.headers)))}',
    );
    final reqData = error.requestOptions.data;
    if (reqData != null) {
      if (reqData is Map && reqData.containsKey('password')) {
        final safe = Map<String, dynamic>.from(reqData);
        safe['password'] = '***';
        _log('Request Body: ${jsonEncode(safe)}');
      } else {
        _log('Request Body: ${_bodyToString(reqData)}');
      }
    }
    _log('Response Status Code: ${error.response?.statusCode ?? 'N/A'}');
    if (error.response?.headers.map.isNotEmpty == true) {
      _log('Response Headers: ${error.response!.headers.map}');
    }
    _log('Response Body:\n${_bodyToString(error.response?.data)}');
    if (stackTrace != null) {
      _log('StackTrace:\n$stackTrace');
    }
  }

  static void logGenericError(Object error, [StackTrace? stackTrace]) {
    _log('═══ ERROR ═══');
    _log('Error: $error');
    if (error is DioException) {
      logDioException(error, stackTrace);
      return;
    }
    if (stackTrace != null) {
      _log('StackTrace:\n$stackTrace');
    }
  }
}
