import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/sync/google_auth.dart';

void main() {
  test('a remembered account counts as signed in without asking Google', () {
    final auth = AuthService(webClientId: '');
    expect(auth.signedIn, isFalse);
    auth.restore('me@x.com');
    expect(auth.signedIn, isTrue);
    expect(auth.email, 'me@x.com');
  });

  test('blank or missing emails do not sign anyone in', () {
    final auth = AuthService(webClientId: '')..restore('  ');
    expect(auth.signedIn, isFalse);
    auth.restore(null);
    expect(auth.signedIn, isFalse);
  });

  test('signing out forgets the remembered account', () async {
    final auth = AuthService(webClientId: '')..restore('me@x.com');
    await auth.signOut();
    expect(auth.signedIn, isFalse);
    expect(auth.email, isNull);
  });
}
