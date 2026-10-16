import '../../store/journal_store.dart';
import '../../sync/google_auth.dart';

const kGoogleSignedInKey = 'googleSignedIn';

bool hasSignedInBefore(JournalStore store) =>
    store.syncData[kGoogleSignedInKey] == true;

/// Returns whether an account is signed in; otherwise the reason is in [AuthService.error].
Future<bool> signInAndRemember(JournalStore store, AuthService auth) async {
  await auth.signIn();
  final email = auth.email;
  if (!auth.signedIn || email == null || email.isEmpty) return false;
  final s = store.settings;
  if (s.me != email) {
    await store.updateSettings(
      AppSettings(
        me: email,
        driveFolderId: s.driveFolderId,
        downloadMedia: s.downloadMedia,
      ),
    );
  }
  store.syncData[kGoogleSignedInKey] = true;
  await store.saveState();
  return true;
}

Future<void> signOutAndForget(JournalStore store, AuthService auth) async {
  await auth.signOut();
  store.syncData.remove(kGoogleSignedInKey);
  await store.saveState();
}
