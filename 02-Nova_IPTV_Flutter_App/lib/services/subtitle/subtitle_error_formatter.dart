import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../repository/locale/panel_api_keys.dart';
import 'subtitle_service.dart';

/// Maps subtitle errors to user-visible messages (UI layer only).
class SubtitleErrorFormatter {
  SubtitleErrorFormatter._();

  static String format(Object error) {
    if (error is SubtitleSearchException) {
      return error.messageKey.tr;
    }

    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = _bodyToString(error.response?.data).toLowerCase();

      if (status == 401) {
        return 'subtitle_unauthorized'.tr;
      }
      if (status == 403) {
        if (body.contains('api-key') ||
            body.contains('api key') ||
            body.contains('invalid api')) {
          return 'subtitle_invalid_api_key'.tr;
        }
        return 'subtitle_forbidden'.tr;
      }
      if (status == 429) {
        return 'subtitle_too_many_requests'.tr;
      }
      if (status != null && status >= 500) {
        return 'subtitle_server_error'.tr;
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'subtitle_search_timeout'.tr;
      }
      if (error.type == DioExceptionType.connectionError) {
        return 'subtitle_connection_error'.tr;
      }

      final detail = error.response?.data;
      if (detail != null) {
        return '${'subtitle_connection_error'.tr}\n${_bodyToString(detail)}';
      }
      return '${'subtitle_connection_error'.tr}\n${error.message ?? error}';
    }

    if (error is TimeoutException) {
      return 'subtitle_search_timeout'.tr;
    }

    return error.toString();
  }

  static String downloadFailureMessage() {
    final apiKey = effectiveOpensubtitlesApiKey;
    final username = effectiveOpensubtitlesUsername;
    final password = effectiveOpensubtitlesPassword;

    if (apiKey.isEmpty) {
      return 'subtitle_api_not_configured'.tr;
    }
    if (username.isEmpty) {
      return 'subtitle_invalid_username'.tr;
    }
    if (password.isEmpty) {
      return 'subtitle_invalid_password'.tr;
    }
    return 'subtitle_login_failed'.tr;
  }

  static String _bodyToString(dynamic data) {
    if (data == null) return '';
    if (data is Map || data is List) {
      try {
        return jsonEncode(data);
      } catch (_) {
        return data.toString();
      }
    }
    return data.toString();
  }
}
