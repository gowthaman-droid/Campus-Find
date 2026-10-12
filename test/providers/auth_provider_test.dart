import 'dart:async';

import 'package:campus_find/models/app_user.dart';
import 'package:campus_find/models/enums.dart';
import 'package:campus_find/providers/auth_provider.dart';
import 'package:campus_find/services/auth_service.dart';
import 'package:campus_find/services/storage_service.dart';
import 'package:campus_find/services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, User;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserService extends Mock implements UserService {}

class MockStorageService extends Mock implements StorageService {}

class MockUser extends Mock implements User {}

void main() {
  late MockAuthService auth;
  late MockUserService users;
  late MockStorageService storage;
  late StreamController<User?> authEvents;
  late StreamController<AppUser?> profileEvents;

  final profile = AppUser(
    uid: 'u1',
    name: 'Asha Kumar',
    email: 'asha@college.edu',
    phone: '9876543210',
    role: UserRole.student,
    createdAt: DateTime(2026, 10, 1),
  );

  MockUser fakeUser({String uid = 'u1', String email = 'asha@college.edu'}) {
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.email).thenReturn(email);
    return user;
  }

  AuthProvider makeProvider() {
    return AuthProvider(auth: auth, users: users, storage: storage);
  }

  /// Signs the fake person in and delivers their profile.
  Future<AuthProvider> signedInProvider() async {
    final provider = makeProvider();
    authEvents.add(fakeUser());
    await pumpEventQueue();
    profileEvents.add(profile);
    await pumpEventQueue();
    return provider;
  }

  setUp(() {
    auth = MockAuthService();
    users = MockUserService();
    storage = MockStorageService();
    authEvents = StreamController<User?>.broadcast();
    profileEvents = StreamController<AppUser?>.broadcast();
    when(() => auth.userChanges).thenAnswer((_) => authEvents.stream);
    when(() => auth.currentUser).thenReturn(null);
    when(() => auth.isAdmin(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => false);
    when(() => users.watchProfile(any()))
        .thenAnswer((_) => profileEvents.stream);
  });

  tearDown(() async {
    await authEvents.close();
    await profileEvents.close();
  });

  group('following Firebase', () {
    test('starts initializing, then signedOut when nobody is signed in', () async {
      final provider = makeProvider();
      expect(provider.status, AuthStatus.initializing);

      authEvents.add(null);
      await pumpEventQueue();

      expect(provider.status, AuthStatus.signedOut);
      provider.dispose();
    });

    test('is signedIn once the profile arrives, and reads the admin flag', () async {
      when(() => auth.isAdmin(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => true);
      final provider = makeProvider();

      authEvents.add(fakeUser());
      await pumpEventQueue();
      expect(provider.status, AuthStatus.initializing); // profile not here yet

      profileEvents.add(profile);
      await pumpEventQueue();

      expect(provider.status, AuthStatus.signedIn);
      expect(provider.profile?.name, 'Asha Kumar');
      expect(provider.uid, 'u1');
      expect(provider.isAdmin, isTrue);
      verify(() => auth.isAdmin(forceRefresh: true)).called(1);
      provider.dispose();
    });

    test('needsProfile when the profile document is missing', () async {
      final provider = makeProvider();
      authEvents.add(fakeUser());
      await pumpEventQueue();
      profileEvents.add(null);
      await pumpEventQueue();

      expect(provider.status, AuthStatus.needsProfile);
      provider.dispose();
    });

    test('profileError when the profile cannot be read', () async {
      final provider = makeProvider();
      authEvents.add(fakeUser());
      await pumpEventQueue();
      profileEvents.addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      await pumpEventQueue();

      expect(provider.status, AuthStatus.profileError);
      expect(provider.profileError, contains('Cannot reach'));
      provider.dispose();
    });

    test('logging out clears everything', () async {
      final provider = await signedInProvider();
      expect(provider.status, AuthStatus.signedIn);

      authEvents.add(null);
      await pumpEventQueue();

      expect(provider.status, AuthStatus.signedOut);
      expect(provider.profile, isNull);
      expect(provider.uid, isNull);
      expect(provider.isAdmin, isFalse);
      provider.dispose();
    });

    test('a refreshed token of the same person does not restart anything', () async {
      final provider = await signedInProvider();

      authEvents.add(fakeUser()); // same uid again
      await pumpEventQueue();

      expect(provider.status, AuthStatus.signedIn);
      verify(() => users.watchProfile(any())).called(1);
      verify(() => auth.isAdmin(forceRefresh: false)).called(1);
      provider.dispose();
    });
  });

  group('signIn', () {
    test('refuses a bad e-mail without calling Firebase', () async {
      final provider = makeProvider();
      final result = await provider.signIn(email: 'nope', password: 'secret123');

      expect(result.success, isFalse);
      expect(result.message, contains('e-mail'));
      verifyNever(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      provider.dispose();
    });

    test('turns a Firebase error into a friendly message', () async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'wrong-password'));
      final provider = makeProvider();

      final result =
          await provider.signIn(email: 'asha@college.edu', password: 'wrong');

      expect(result.success, isFalse);
      expect(result.message, 'E-mail or password is incorrect.');
      expect(provider.busy, isFalse);
      provider.dispose();
    });

    test('a second tap while busy is refused', () async {
      final gate = Completer<User>();
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) => gate.future);
      final provider = makeProvider();

      final first =
          provider.signIn(email: 'asha@college.edu', password: 'secret123');
      await pumpEventQueue();
      expect(provider.busy, isTrue);

      final second =
          await provider.signIn(email: 'asha@college.edu', password: 'secret123');
      expect(second.success, isFalse);
      expect(second.message, contains('wait'));

      gate.complete(fakeUser());
      expect((await first).success, isTrue);
      provider.dispose();
    });
  });

  group('register', () {
    void stubRegister() {
      // Create the fake user BEFORE stubbing: mocktail does not allow
      // `when(...)` to be called inside a stub's answer.
      final user = fakeUser();
      when(
        () => auth.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => user);
    }

    test('creates the account and the profile', () async {
      stubRegister();
      when(
        () => users.createProfile(
          uid: any(named: 'uid'),
          name: any(named: 'name'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
        ),
      ).thenAnswer((_) async {});
      final provider = makeProvider();

      final result = await provider.register(
        name: 'Asha Kumar',
        email: 'asha@college.edu',
        phone: '9876543210',
        password: 'secret123',
      );

      expect(result.success, isTrue);
      verify(
        () => users.createProfile(
          uid: 'u1',
          name: 'Asha Kumar',
          email: 'asha@college.edu',
          phone: '9876543210',
        ),
      ).called(1);
      provider.dispose();
    });

    test('removes the half-created account when the profile cannot be saved', () async {
      stubRegister();
      when(
        () => users.createProfile(
          uid: any(named: 'uid'),
          name: any(named: 'name'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
        ),
      ).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      when(() => auth.deleteCurrentUser()).thenAnswer((_) async {});
      final provider = makeProvider();

      final result = await provider.register(
        name: 'Asha Kumar',
        email: 'asha@college.edu',
        phone: '9876543210',
        password: 'secret123',
      );

      expect(result.success, isFalse);
      verify(() => auth.deleteCurrentUser()).called(1);
      provider.dispose();
    });

    test('refuses invalid input without calling Firebase', () async {
      final provider = makeProvider();

      final result = await provider.register(
        name: 'A',
        email: 'bad',
        phone: '1',
        password: '123',
      );

      expect(result.success, isFalse);
      verifyNever(
        () => auth.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      );
      provider.dispose();
    });
  });

  group('other actions', () {
    test('sendPasswordReset gives the same answer for any e-mail', () async {
      when(() => auth.sendPasswordReset(any())).thenAnswer((_) async {});
      final provider = makeProvider();

      final result = await provider.sendPasswordReset('someone@college.edu');

      expect(result.success, isTrue);
      expect(result.message, contains('If an account exists'));
      provider.dispose();
    });

    test('updateProfile saves the new name and phone', () async {
      when(
        () => users.updateProfile(
          uid: any(named: 'uid'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          profileImage: any(named: 'profileImage'),
        ),
      ).thenAnswer((_) async {});
      final provider = await signedInProvider();

      final result =
          await provider.updateProfile(name: 'Asha K', phone: '9876543210');

      expect(result.success, isTrue);
      verify(
        () => users.updateProfile(
          uid: 'u1',
          name: 'Asha K',
          phone: '9876543210',
          profileImage: '',
        ),
      ).called(1);
      provider.dispose();
    });

    test('updateProfile needs a signed-in person', () async {
      final provider = makeProvider();
      final result =
          await provider.updateProfile(name: 'Asha K', phone: '9876543210');

      expect(result.success, isFalse);
      provider.dispose();
    });
  });
}
