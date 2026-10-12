import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/match_result.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';
import '../utils/parsers.dart';

/// Gives the current Firebase ID token (or null when nobody is signed in).
/// [forceRefresh] asks Firebase for a brand-new token.
/// `AuthService.getIdToken` has exactly this shape.
typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// Event names understood by `POST /events` (see docs/API.md).
class ApiEvents {
  ApiEvents._();

  static const String claimSubmitted = 'claim_submitted';
  static const String claimApproved = 'claim_approved';
  static const String claimRejected = 'claim_rejected';
  static const String claimCompleted = 'claim_completed';
  static const String itemReturned = 'item_returned';
}

class EventResult {
  const EventResult({required this.created, required this.pushed});

  final int created;
  final int pushed;
}

class BroadcastResult {
  const BroadcastResult({required this.recipients, required this.pushed});

  final int recipients;
  final bool pushed;
}

class RematchResult {
  const RematchResult({
    required this.processed,
    required this.succeeded,
    required this.failed,
  });

  final int processed;
  final int succeeded;
  final int failed;
}

/// Talks to the Python (FastAPI) service. Every call except [isHealthy]
/// sends `Authorization: Bearer <Firebase ID token>`.
///
/// Problems are thrown as [ApiException]:
///  * statusCode 0   -> no answer at all (offline, service stopped, timeout)
///  * statusCode 4xx -> the service refused; the message is safe to show
///  * statusCode 5xx -> a generic message is used (server details are never shown)
class BackendApiService {
  BackendApiService({
    required TokenProvider tokenProvider,
    http.Client? client,
    String? baseUrl,
    Duration? timeout,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? http.Client(),
        _baseUrl = _withoutTrailingSlash(baseUrl ?? AppConfig.apiBaseUrl),
        _timeout = timeout ?? AppConstants.apiTimeout;

  final TokenProvider _tokenProvider;
  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  void close() => _client.close();

  // ---------------------------------------------------------------------
  // Public endpoints (docs/API.md)
  // ---------------------------------------------------------------------

  /// `GET /health`. Never throws: true when the service answers "ok".
  Future<bool> isHealthy({bool deep = false}) async {
    try {
      final json = await _request(
        'GET',
        '/health',
        query: deep ? <String, String>{'deep': 'true'} : null,
        authenticated: false,
      );
      return readString(json, 'status') == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// `POST /match`: find matches for one report and notify people.
  Future<MatchResponse> match(String reportId) async {
    final json = await _request(
      'POST',
      '/match',
      body: <String, dynamic>{'report_id': reportId},
    );
    return MatchResponse.fromJson(json);
  }

  /// `POST /events`: ask the server to notify the other person after a claim
  /// action. Use the names in [ApiEvents].
  Future<EventResult> sendEvent(
    String type, {
    String? claimId,
    String? reportId,
  }) async {
    final body = <String, dynamic>{'type': type};
    if (claimId != null) {
      body['claim_id'] = claimId;
    }
    if (reportId != null) {
      body['report_id'] = reportId;
    }
    final json = await _request('POST', '/events', body: body);
    return EventResult(
      created: readInt(json, 'created'),
      pushed: readInt(json, 'pushed'),
    );
  }

  // ---------------------------------------------------------------------
  // Admin endpoints (the service checks the admin claim)
  // ---------------------------------------------------------------------

  /// `POST /admin/users/{uid}/role` with `student` or `admin`.
  Future<void> setUserRole(String uid, String role) async {
    await _request(
      'POST',
      '/admin/users/${Uri.encodeComponent(uid)}/role',
      body: <String, dynamic>{'role': role},
    );
  }

  /// `POST /admin/users/{uid}/disabled`
  Future<void> setUserDisabled(String uid, bool disabled) async {
    await _request(
      'POST',
      '/admin/users/${Uri.encodeComponent(uid)}/disabled',
      body: <String, dynamic>{'disabled': disabled},
    );
  }

  /// `POST /admin/notifications`: a message to one person ([userId]) or to everyone.
  Future<BroadcastResult> sendAdminMessage({
    required String title,
    required String body,
    String? userId,
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'audience': userId == null ? 'all' : 'user',
    };
    if (userId != null) {
      payload['user_id'] = userId;
    }
    final json = await _request('POST', '/admin/notifications', body: payload);
    return BroadcastResult(
      recipients: readInt(json, 'recipients'),
      pushed: readBool(json, 'pushed'),
    );
  }

  /// `POST /admin/rematch`: run matching again for reports whose matching is
  /// pending or failed.
  Future<RematchResult> rematch({int limit = 50}) async {
    final json = await _request(
      'POST',
      '/admin/rematch',
      query: <String, String>{'limit': '$limit'},
    );
    return RematchResult(
      processed: readInt(json, 'processed'),
      succeeded: readInt(json, 'succeeded'),
      failed: readInt(json, 'failed'),
    );
  }

  // ---------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------

  static String _withoutTrailingSlash(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) {
      return base;
    }
    return base.replace(queryParameters: query);
  }

  Future<http.Response> _sendOnce(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: body);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: body);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }

  /// Sends a request and returns the decoded JSON object.
  /// A 401 answer is retried once with a freshly issued token.
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final uri = _uri(path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    var forceRefresh = false;

    for (var attempt = 0; attempt < 2; attempt++) {
      final headers = <String, String>{'Accept': 'application/json'};
      if (encodedBody != null) {
        headers['Content-Type'] = 'application/json';
      }
      if (authenticated) {
        final token = await _tokenProvider(forceRefresh: forceRefresh);
        if (token == null || token.isEmpty) {
          throw const ApiException(
            'Please log in again.',
            statusCode: 401,
            code: 'unauthenticated',
          );
        }
        headers['Authorization'] = 'Bearer $token';
      }

      final http.Response response;
      try {
        response =
            await _sendOnce(method, uri, headers, encodedBody).timeout(_timeout);
      } on TimeoutException {
        throw const ApiException(
          'The Campus Find service did not answer in time. Please try again.',
          statusCode: 0,
          code: 'timeout',
        );
      } on http.ClientException {
        throw const ApiException(
          'Cannot reach the Campus Find service. '
          'Please check your internet connection and try again.',
          statusCode: 0,
          code: 'unreachable',
        );
      }

      if (response.statusCode == 401 && authenticated && attempt == 0) {
        forceRefresh = true;
        continue;
      }
      return _decode(response);
    }
    throw const ApiException(
      'Please log in again.',
      statusCode: 401,
      code: 'unauthenticated',
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    Object? parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } on FormatException {
        parsed = null;
      }
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
      if (parsed == null) {
        return <String, dynamic>{};
      }
      throw ApiException(
        'The service sent a reply the app could not read.',
        statusCode: status,
        code: 'bad_response',
      );
    }
    throw _errorFrom(status, parsed);
  }

  /// Builds the error from the service's standard error body
  /// `{"error": {"code": ..., "message": ..., "details": ...}}`.
  /// The service's own message is shown only for 4xx answers; for 5xx a
  /// generic sentence is used so technical details never reach the screen.
  ApiException _errorFrom(int status, Object? parsed) {
    String? code;
    String? serverMessage;
    Object? details;
    if (parsed is Map) {
      final error = parsed['error'];
      if (error is Map) {
        final rawCode = error['code'];
        final rawMessage = error['message'];
        if (rawCode is String) {
          code = rawCode;
        }
        if (rawMessage is String) {
          serverMessage = rawMessage;
        }
        details = error['details'];
      }
    }
    final trusted = status >= 400 &&
        status < 500 &&
        serverMessage != null &&
        serverMessage.trim().isNotEmpty;
    return ApiException(
      trusted ? serverMessage : _defaultMessage(status),
      statusCode: status,
      code: code,
      details: details,
    );
  }

  String _defaultMessage(int status) {
    switch (status) {
      case 401:
        return 'Your session has expired. Please log in again.';
      case 403:
        return 'You are not allowed to do that.';
      case 404:
        return 'That could not be found.';
      case 409:
        return 'That conflicts with the current state. Please refresh and try again.';
      case 422:
        return 'Some of the details are not valid.';
      case 503:
        return 'The Campus Find service is temporarily unavailable. Please try again later.';
      default:
        return 'The Campus Find service had a problem. Please try again later.';
    }
  }
}
