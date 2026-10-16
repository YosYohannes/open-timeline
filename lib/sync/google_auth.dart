import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;

import '../config.dart';

/// Google Sign-In (google_sign_in v7) plus a ready-to-use [DriveApi].
///
/// Full Drive scope is needed: the narrower `drive.file` scope cannot see files
/// the partner created in the shared folder.
///
/// No method throws. Problems are kept in [error] (null when everything is fine);
/// the user pressing "cancel" is not an error.
class AuthService extends ChangeNotifier {
  AuthService({this.webClientId = kGoogleWebClientId});

  /// OAuth Web client ID (see lib/config.dart).
  final String webClientId;

  static const _scope = DriveApi.driveScope;
  static const _notConfigured =
      'Google sign-in is not set up: kGoogleWebClientId in lib/config.dart is empty.';

  GoogleSignInAccount? _account;
  String? _error;
  bool _initialized = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  void Function()? _closeHttp;
  String? _lastToken;

  /// Email of the signed-in account, or null.
  String? get email => _account?.email;

  bool get signedIn => _account != null;

  /// True when a Web client ID is configured.
  bool get configured => webClientId.isNotEmpty;

  /// Last problem, in words the user can read. Cleared by the next successful call.
  String? get error => _error;

  /// Call once at startup. Initializes the plugin and, when [attemptSilent] is
  /// true, restores a previous sign-in without (much) UI. Note that on Android
  /// the plugin may show the account chooser sheet if nobody has signed in yet;
  /// pass false until the user has signed in once (e.g. when `settings.me` is empty).
  Future<void> init({bool attemptSilent = true}) async {
    if (!configured) {
      _error = _notConfigured;
      notifyListeners();
      return;
    }
    try {
      if (!_initialized) {
        await GoogleSignIn.instance.initialize(serverClientId: webClientId);
        _initialized = true;
        _events = GoogleSignIn.instance.authenticationEvents.listen((event) {
          switch (event) {
            case GoogleSignInAuthenticationEventSignIn():
              _setAccount(event.user);
            case GoogleSignInAuthenticationEventSignOut():
              _setAccount(null);
          }
        }, onError: (Object _) {});
      }
      if (attemptSilent && _account == null) {
        final attempt = GoogleSignIn.instance
            .attemptLightweightAuthentication();
        if (attempt != null) _setAccount(await attempt);
      }
      _error = null;
    } catch (e) {
      _error = _describe(e);
    }
    notifyListeners();
  }

  /// Interactive sign-in, followed by the Drive permission prompt so that later
  /// syncs need no UI. Read [email] / [error] afterwards.
  Future<void> signIn() async {
    if (!configured) {
      _error = _notConfigured;
      notifyListeners();
      return;
    }
    if (!_initialized) {
      await init(attemptSilent: false);
      if (!_initialized) return;
    }
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [_scope],
      );
      _setAccount(account);
      _error = null;
      notifyListeners();
      try {
        await account.authorizationClient.authorizeScopes(const [_scope]);
      } catch (e) {
        if (!_isCancel(e)) {
          _error = 'Google Drive access was not granted: ${_describe(e)}';
        }
      }
    } catch (e) {
      _error = _isCancel(e) ? null : _describe(e);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      if (_initialized) await GoogleSignIn.instance.signOut();
      _error = null;
    } catch (e) {
      _error = _describe(e);
    }
    _setAccount(null);
    notifyListeners();
  }

  /// A [DriveApi] with a fresh access token, or null when signed out or Drive
  /// access has not been granted. With [interactive] true the permission prompt
  /// may be shown (only call that from a button press). Tokens last about an
  /// hour, so ask again for each sync instead of keeping the result.
  Future<DriveApi?> driveApi({bool interactive = false}) async {
    final account = _account;
    if (!_initialized || account == null) return null;
    try {
      final client = account.authorizationClient;
      var authz = await client.authorizationForScopes(const [_scope]);
      if (authz == null && interactive) {
        authz = await client.authorizeScopes(const [_scope]);
      }
      if (authz == null) return null;
      _lastToken = authz.accessToken;
      final http = authz.authClient(scopes: const [_scope]);
      _closeHttp?.call(); // the previous sync is over
      _closeHttp = http.close;
      return DriveApi(http);
    } catch (e) {
      _error = _isCancel(e) ? null : _describe(e);
      notifyListeners();
      return null;
    }
  }

  /// Forget the cached access token (call after Drive answered 401) so the next
  /// [driveApi] fetches a new one.
  Future<void> invalidateToken() async {
    final token = _lastToken;
    final account = _account;
    if (token == null || account == null || !_initialized) return;
    try {
      await account.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
    } catch (_) {}
    _lastToken = null;
  }

  void _setAccount(GoogleSignInAccount? account) {
    if (_account == account) return;
    _account = account;
    if (account == null) {
      _closeHttp?.call();
      _closeHttp = null;
      _lastToken = null;
    }
    notifyListeners();
  }

  static bool _isCancel(Object e) =>
      e is GoogleSignInException &&
      (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted);

  static String _describe(Object e) {
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google sign-in is misconfigured (check the OAuth client IDs and the app signing key '
              'in Google Cloud): ${e.description ?? e.code.name}';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Google sign-in cannot be shown right now. Try again.';
        case GoogleSignInExceptionCode.userMismatch:
          return 'A different Google account is signed in. Sign out first.';
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
        case GoogleSignInExceptionCode.unknownError:
          return 'Google sign-in failed: ${e.description ?? e.code.name}';
      }
    }
    return 'Google sign-in failed: $e';
  }

  @override
  void dispose() {
    _events?.cancel();
    _closeHttp?.call();
    super.dispose();
  }
}
