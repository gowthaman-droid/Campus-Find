import 'dart:convert';

import 'package:campus_find/services/backend_api_service.dart';
import 'package:campus_find/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a service that talks to a fake server instead of the network.
/// [refreshLog] records the `forceRefresh` flag of every token request.
BackendApiService makeService(
  MockClientHandler handler, {
  List<bool>? refreshLog,
  String? token = 'token-1',
  Duration? timeout,
}) {
  return BackendApiService(
    tokenProvider: ({bool forceRefresh = false}) async {
      refreshLog?.add(forceRefresh);
      return token;
    },
    client: MockClient(handler),
    baseUrl: 'http://test.local:8000/',
    timeout: timeout,
  );
}

http.Response jsonResponse(Object body, int status) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

void main() {
  group('match', () {
    test('sends a POST with the bearer token and reads the answer', () async {
      late http.Request seen;
      final service = makeService((request) async {
        seen = request;
        return jsonResponse(<String, dynamic>{
          'report_id': 'rep1',
          'match': true,
          'score': 87,
          'matched_report_id': 'abc123',
          'matches': <dynamic>[],
          'evaluated': 14,
        }, 200);
      });

      final result = await service.match('rep1');

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://test.local:8000/match');
      expect(seen.headers['Authorization'], 'Bearer token-1');
      expect(jsonDecode(seen.body), <String, dynamic>{'report_id': 'rep1'});
      expect(result.match, isTrue);
      expect(result.score, 87);
      expect(result.matchedReportId, 'abc123');
      expect(result.evaluated, 14);
    });

    test('turns the standard error body into an ApiException', () async {
      final service = makeService((request) async {
        return jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'report_not_found',
            'message': 'No report with that id.',
            'details': null,
          },
        }, 404);
      });

      await expectLater(
        service.match('x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.code, 'code', 'report_not_found')
              .having((e) => e.message, 'message', 'No report with that id.'),
        ),
      );
    });

    test('never shows server details for 5xx errors', () async {
      final service = makeService((request) async {
        return jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'internal_error',
            'message': 'Traceback: secret stack trace',
          },
        }, 500);
      });

      try {
        await service.match('x');
        fail('An ApiException was expected');
      } on ApiException catch (error) {
        expect(error.statusCode, 500);
        expect(error.message, isNot(contains('secret')));
      }
    });

    test('a 409 answer is a conflict', () async {
      final service = makeService((request) async {
        return jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'report_not_active',
            'message': 'This report is not active.',
          },
        }, 409);
      });

      await expectLater(
        service.match('x'),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'isConflict', true)),
      );
    });
  });

  group('authentication', () {
    test('retries once with a fresh token after a 401', () async {
      final refreshLog = <bool>[];
      var calls = 0;
      final service = makeService((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('{}', 401);
        }
        return jsonResponse(<String, dynamic>{'created': 1, 'pushed': 1}, 200);
      }, refreshLog: refreshLog);

      final result =
          await service.sendEvent(ApiEvents.claimSubmitted, claimId: 'c1');

      expect(calls, 2);
      expect(refreshLog, <bool>[false, true]);
      expect(result.created, 1);
      expect(result.pushed, 1);
    });

    test('does not call the service without a token', () async {
      var called = false;
      final service = makeService((request) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null);

      await expectLater(
        service.match('x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(called, isFalse);
    });
  });

  group('connection problems', () {
    test('an unreachable service has statusCode 0', () async {
      final service = makeService((request) async {
        throw http.ClientException('connection refused');
      });

      await expectLater(
        service.match('x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 0)
              .having((e) => e.isServiceUnavailable, 'isServiceUnavailable', true),
        ),
      );
    });

    test('a slow service ends in a timeout error', () async {
      final service = makeService(
        (request) async {
          return Future<http.Response>.delayed(
            const Duration(milliseconds: 300),
            () => http.Response('{}', 200),
          );
        },
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.match('x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'timeout')),
      );
    });

    test('isHealthy sends no token and never throws', () async {
      String? authHeader = 'untouched';
      final healthy = makeService((request) async {
        authHeader = request.headers['Authorization'];
        return jsonResponse(<String, dynamic>{'status': 'ok'}, 200);
      });
      expect(await healthy.isHealthy(), isTrue);
      expect(authHeader, isNull);

      final down = makeService((request) async {
        throw http.ClientException('down');
      });
      expect(await down.isHealthy(), isFalse);
    });
  });

  group('admin calls', () {
    test('rematch passes the limit as a query parameter', () async {
      late Uri seenUrl;
      final service = makeService((request) async {
        seenUrl = request.url;
        return jsonResponse(
          <String, dynamic>{'processed': 3, 'succeeded': 2, 'failed': 1},
          200,
        );
      });

      final result = await service.rematch(limit: 25);

      expect(seenUrl.path, '/admin/rematch');
      expect(seenUrl.queryParameters['limit'], '25');
      expect(result.processed, 3);
      expect(result.failed, 1);
    });

    test('sendAdminMessage targets everyone or one person', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = makeService((request) async {
        bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return jsonResponse(
          <String, dynamic>{'recipients': 5, 'pushed': true},
          200,
        );
      });

      final everyone =
          await service.sendAdminMessage(title: ' Hello ', body: 'Desk is open');
      await service.sendAdminMessage(
        title: 'Hi',
        body: 'Your item',
        userId: 'uid1',
      );

      expect(everyone.recipients, 5);
      expect(everyone.pushed, isTrue);
      expect(bodies[0]['audience'], 'all');
      expect(bodies[0]['title'], 'Hello');
      expect(bodies[0].containsKey('user_id'), isFalse);
      expect(bodies[1]['audience'], 'user');
      expect(bodies[1]['user_id'], 'uid1');
    });

    test('setUserRole puts the user id in the path', () async {
      late http.Request seen;
      final service = makeService((request) async {
        seen = request;
        return jsonResponse(<String, dynamic>{'uid': 'u 1', 'role': 'admin'}, 200);
      });

      await service.setUserRole('u 1', 'admin');

      expect(seen.url.path, '/admin/users/u%201/role');
      expect(jsonDecode(seen.body), <String, dynamic>{'role': 'admin'});
    });
  });
}
