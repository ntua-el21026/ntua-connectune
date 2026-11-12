import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_around/auth/forgot_pass.dart';
import 'package:listen_around/auth/login.dart';

void main() {
  testWidgets('password reset is reachable from login and returns to the form',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.enterText(
        find.byType(TextField).first, 'listener@example.test');

    final resetLink = find.text('Forgot Password?');
    expect(resetLink, findsOneWidget);
    await tester.ensureVisible(resetLink);
    await tester.tap(resetLink);
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordPage), findsOneWidget);
    expect(
        find.widgetWithText(ElevatedButton, 'Reset Password'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordPage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('listener@example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
