import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';

const kGoogleSignedInKey = 'googleSignedIn';
const kGoogleEmailKey = 'googleEmail';

String? rememberedGoogleEmail(JournalStore store) =>
    store.syncData[kGoogleSignedInKey] == true
    ? (store.syncData[kGoogleEmailKey] as String?) ?? store.settings.me
    : null;

/// Returns whether an account is signed in; otherwise the reason is in [AuthService.error].
Future<bool> signInAndRemember(JournalStore store, AuthService auth) async {
  await auth.signIn();
  final email = auth.email;
  if (!auth.signedIn || email == null || email.isEmpty) return false;
  final s = store.settings;
  if (s.me != email) {
    await store.updateSettings(s.copyWith(me: email));
  }
  store.syncData[kGoogleSignedInKey] = true;
  store.syncData[kGoogleEmailKey] = email;
  await store.saveState();
  return true;
}

Future<void> signOutAndForget(JournalStore store, AuthService auth) async {
  await auth.signOut();
  store.syncData.remove(kGoogleSignedInKey);
  store.syncData.remove(kGoogleEmailKey);
  await store.saveState();
}
