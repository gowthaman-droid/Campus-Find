import 'dart:async';

import 'package:campus_find/utils/app_exception.dart';
import 'package:campus_find/utils/formatters.dart';
import 'package:campus_find/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('asha@college.edu'), isNull);
      expect(Validators.email('  asha@college.edu  '), isNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('asha@'), isNotNull);
      expect(Validators.email('asha college@x.com'), isNotNull);
    });

    test('password needs at least 8 characters', () {
      expect(Validators.password('12345678'), isNull);
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password(null), isNotNull);
    });

    test('confirmPassword compares with the first field', () {
      final check = Validators.confirmPassword(() => 'secret123');
      expect(check('secret123'), isNull);
      expect(check('other'), isNotNull);
      expect(check(''), isNotNull);
    });

    test('phone accepts spaces, dashes and a leading plus', () {
      expect(Validators.phone('+91 98765-43210'), isNull);
      expect(Validators.phone('9876543210'), isNull);
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('abc'), isNotNull);
      expect(Validators.phone(''), isNotNull);
    });

    test('lengthBetween and notEmpty', () {
      final check = Validators.lengthBetween('Name', 2, 5);
      expect(check('abc'), isNull);
      expect(check('a'), isNotNull);
      expect(check('abcdef'), isNotNull);
      expect(check('   '), isNotNull);
      final location = Validators.notEmpty('Location');
      expect(location(''), 'Location is required');
      expect(location('Library'), isNull);
    });

    test('description needs 10 characters in the form', () {
      expect(Validators.description('too short'), isNotNull);
      expect(Validators.description('Brown leather, college ID inside'), isNull);
    });
  });

  group('Fmt', () {
    test('timeAgo', () {
      final now = DateTime(2026, 10, 7, 12, 0);
      expect(Fmt.timeAgo(DateTime(2026, 10, 7, 11, 59, 50), now: now), 'just now');
      expect(Fmt.timeAgo(DateTime(2026, 10, 7, 11, 55), now: now), '5 min ago');
      expect(Fmt.timeAgo(DateTime(2026, 10, 7, 9, 0), now: now), '3 h ago');
      expect(Fmt.timeAgo(DateTime(2026, 10, 5, 12, 0), now: now), '2 d ago');
    });

    test('scoreLabel uses the match thresholds', () {
      expect(Fmt.scoreLabel(87), 'Strong match');
      expect(Fmt.scoreLabel(60), 'Possible match');
      expect(Fmt.scoreLabel(40), 'Weak match');
    });

    test('initials and phone cleaning', () {
      expect(Fmt.initials('Asha Kumar'), 'AK');
      expect(Fmt.initials('asha'), 'A');
      expect(Fmt.initials('  '), '?');
      expect(Fmt.normalizePhone('+91 98765-43210'), '+919876543210');
    });
  });

  group('friendlyError', () {
    test('shows the message of an AppException', () {
      expect(friendlyError(const AppException('Hello')), 'Hello');
    });

    test('explains timeouts', () {
      expect(friendlyError(TimeoutException('x')), contains('too long'));
    });

    test('never leaks the text of unknown errors', () {
      final text = friendlyError(Exception('secret internal detail'));
      expect(text, isNot(contains('secret')));
      expect(text, contains('Something went wrong'));
    });

    test('connectivity problems are recognised', () {
      expect(isConnectivityProblem(TimeoutException('x')), isTrue);
      expect(
        isConnectivityProblem(const ApiException('x', statusCode: 503)),
        isTrue,
      );
      expect(
        isConnectivityProblem(const ApiException('x', statusCode: 409)),
        isFalse,
      );
    });
  });
}
