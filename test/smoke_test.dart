import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/main.dart';
import 'package:open_timeline/sync/google_auth.dart';

void main() {
  testWidgets('login check screen builds without a client ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      OpenTimelineApp(auth: AuthService(webClientId: '')),
    );
    await tester.pump();
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.textContaining('kGoogleWebClientId'), findsWidgets);
  });
}
