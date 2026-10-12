import 'package:campus_find/models/app_user.dart';
import 'package:campus_find/models/claim.dart';
import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/report.dart';
import 'package:campus_find/providers/claim_provider.dart';
import 'package:campus_find/services/claim_service.dart';
import 'package:campus_find/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockClaimService extends Mock implements ClaimService {}

final AppUser profile = AppUser(
  uid: 'u1',
  name: 'Asha Kumar',
  email: 'asha@college.edu',
  phone: '9876543210',
  role: UserRole.student,
  createdAt: DateTime(2026, 10, 1),
);

Claim makeClaim(
  String reportId,
  String claimantId, {
  String status = 'pending',
  String owner = 'finder',
}) {
  return Claim.fromMap('${reportId}_$claimantId', <String, dynamic>{
    'reportId': reportId,
    'reportOwnerId': owner,
    'claimantId': claimantId,
    'claimantName': 'Claimant $claimantId',
    'reportItemName': 'Wallet',
    'status': status,
  });
}

Report foundReport() {
  return Report.fromMap('f1', <String, dynamic>{
    'type': 'found',
    'userId': 'finder',
    'itemName': 'Wallet',
  });
}

void main() {
  late MockClaimService claims;

  setUpAll(() {
    registerFallbackValue(makeClaim('fallback', 'x'));
    registerFallbackValue(foundReport());
    registerFallbackValue(profile);
  });

  setUp(() {
    claims = MockClaimService();
    when(() => claims.watchMyClaims(any()))
        .thenAnswer((_) => Stream<List<Claim>>.value(<Claim>[]));
    when(() => claims.watchIncomingClaims(any()))
        .thenAnswer((_) => Stream<List<Claim>>.value(<Claim>[]));
  });

  ClaimProvider makeProvider() => ClaimProvider(claims: claims);

  void stubSubmit({required bool notified}) {
    when(
      () => claims.submitClaim(
        report: any(named: 'report'),
        claimant: any(named: 'claimant'),
        message: any(named: 'message'),
        verificationDetails: any(named: 'verificationDetails'),
      ),
    ).thenAnswer((_) async => notified);
  }

  test('live lists: counts the claims waiting for my review', () async {
    when(() => claims.watchMyClaims(any())).thenAnswer(
      (_) => Stream<List<Claim>>.value(
        <Claim>[makeClaim('f9', 'u1', status: 'approved', owner: 'someone')],
      ),
    );
    when(() => claims.watchIncomingClaims(any())).thenAnswer(
      (_) => Stream<List<Claim>>.value(<Claim>[
        makeClaim('f1', 'u2'),
        makeClaim('f1', 'u3'),
        makeClaim('f2', 'u4', status: 'approved'),
      ]),
    );
    final provider = makeProvider();

    provider.bindUser(profile);
    await pumpEventQueue();

    expect(provider.pendingIncomingCount, 2);
    expect(provider.myClaimFor('f9')?.isApproved, isTrue);
    expect(provider.myClaimFor('nothing'), isNull);
    expect(provider.incomingFor('f1').length, 2);
    expect(provider.loading, isFalse);
    provider.dispose();
  });

  group('submitClaim', () {
    test('tells the person the finder will review the claim', () async {
      stubSubmit(notified: true);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitClaim(
        report: foundReport(),
        message: 'It is my wallet',
        verificationDetails: 'Has a bus pass inside',
      );

      expect(result.success, isTrue);
      expect(result.isWarning, isFalse);
      expect(result.message, contains('finder will review'));
      provider.dispose();
    });

    test('is a warning when the finder could not be notified', () async {
      stubSubmit(notified: false);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitClaim(
        report: foundReport(),
        message: 'It is my wallet',
        verificationDetails: 'Has a bus pass inside',
      );

      expect(result.success, isTrue);
      expect(result.isWarning, isTrue);
      provider.dispose();
    });

    test('shows the service message when the claim is refused', () async {
      when(
        () => claims.submitClaim(
          report: any(named: 'report'),
          claimant: any(named: 'claimant'),
          message: any(named: 'message'),
          verificationDetails: any(named: 'verificationDetails'),
        ),
      ).thenThrow(
        const AppException('This item has already been claimed or returned.'),
      );
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitClaim(
        report: foundReport(),
        message: 'It is my wallet',
        verificationDetails: 'Has a bus pass inside',
      );

      expect(result.success, isFalse);
      expect(result.message, 'This item has already been claimed or returned.');
      expect(provider.busy, isFalse);
      provider.dispose();
    });

    test('needs a signed-in person', () async {
      final provider = makeProvider();

      final result = await provider.submitClaim(
        report: foundReport(),
        message: 'It is my wallet',
        verificationDetails: 'Has a bus pass inside',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Please log in first.');
      provider.dispose();
    });
  });

  group('reviewing', () {
    test('approve uses my id as the reviewer', () async {
      when(
        () => claims.approveClaim(
          claim: any(named: 'claim'),
          reviewerUid: any(named: 'reviewerUid'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => true);
      final provider = makeProvider();
      provider.bindUser(profile);
      final claim = makeClaim('f1', 'u2');

      final result = await provider.approve(claim);

      expect(result.success, isTrue);
      expect(result.message, contains('Claim approved'));
      verify(
        () => claims.approveClaim(claim: claim, reviewerUid: 'u1', note: ''),
      ).called(1);
      provider.dispose();
    });

    test('complete marks the item as returned', () async {
      when(
        () => claims.completeClaim(
          claim: any(named: 'claim'),
          reviewerUid: any(named: 'reviewerUid'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => true);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result =
          await provider.complete(makeClaim('f1', 'u2', status: 'approved'));

      expect(result.success, isTrue);
      expect(result.message, contains('returned'));
      provider.dispose();
    });

    test('reject with a missing notification is a warning, not a failure', () async {
      when(
        () => claims.rejectClaim(
          claim: any(named: 'claim'),
          reviewerUid: any(named: 'reviewerUid'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => false);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result =
          await provider.reject(makeClaim('f1', 'u2'), note: 'Not matching');

      expect(result.success, isTrue);
      expect(result.isWarning, isTrue);
      provider.dispose();
    });

    test('withdraw takes back my own claim', () async {
      when(
        () => claims.withdrawClaim(
          claim: any(named: 'claim'),
          claimantUid: any(named: 'claimantUid'),
        ),
      ).thenAnswer((_) async {});
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.withdraw(makeClaim('f1', 'u1'));

      expect(result.success, isTrue);
      expect(result.message, 'Claim withdrawn.');
      provider.dispose();
    });

    test('review actions need a signed-in person', () async {
      final provider = makeProvider();

      final result = await provider.approve(makeClaim('f1', 'u2'));

      expect(result.success, isFalse);
      verifyNever(
        () => claims.approveClaim(
          claim: any(named: 'claim'),
          reviewerUid: any(named: 'reviewerUid'),
          note: any(named: 'note'),
        ),
      );
      provider.dispose();
    });
  });
}
