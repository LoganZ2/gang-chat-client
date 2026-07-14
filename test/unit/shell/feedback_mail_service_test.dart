import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/shell/feedback_mail_service.dart';

void main() {
  test('feedback mail draft builds a mailto URI with sender metadata', () {
    final uri = FeedbackMailDraft(
      from: 'user@example.test',
      to: 'gang-chat@outlook.com',
      subject: 'Subject',
      body: 'Body',
    ).toMailtoUri();

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'gang-chat@outlook.com');
    expect(uri.queryParameters['from'], 'user@example.test');
    expect(uri.queryParameters['subject'], 'Subject');
    expect(uri.queryParameters['body'], 'Body');
  });
}
