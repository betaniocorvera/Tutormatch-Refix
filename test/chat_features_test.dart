// ─────────────────────────────────────────────────────────────────────────────
// The unlocked conversation: rich sends, session answers, call lines, and the
// pieces of the composer that do not need a device (emoji, delivery, viewer).
//
// The image picker itself is never called here: the bytes it would hand over
// are already in the sample data, and that is what the viewer test opens.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutormatch/data/mock_data.dart';
import 'package:tutormatch/screens/chat_screen.dart';
import 'package:tutormatch/state/app_state.dart';
import 'package:tutormatch/theme/app_theme.dart';

final Uint8List _redDot = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);

Future<void> _pumpChat(
  WidgetTester tester,
  AppState state,
  String conversationId, {
  Size size = const Size(900, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppStateScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: ChatScreen(conversationId: conversationId),
      ),
    ),
  );
  // The thread jumps to its foot after the first frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a photo, a voice note and a proposal land as their own kinds',
      (WidgetTester tester) async {
    final AppState state = AppState();
    final int before = state.conversation('c-1045')!.messages.length;

    state.sendImage('c-1045', _redDot);
    ChatMessage sent = state.conversation('c-1045')!.messages.last;
    expect(sent.kind, MessageKind.image);
    expect(sent.image, _redDot);
    expect(sent.fromMe, isTrue);

    state.sendVoice('c-1045', 14);
    sent = state.conversation('c-1045')!.messages.last;
    expect(sent.kind, MessageKind.voice);
    expect(sent.seconds, 14);
    expect(sent.text, 'Voice note · 0:14');

    final DateTime at = DateTime(2026, 11, 3, 16, 45);
    state.proposeSession('c-1045', at);
    sent = state.conversation('c-1045')!.messages.last;
    expect(sent.kind, MessageKind.session);
    expect(sent.sessionWhen, describeSession(at));
    expect(sent.sessionState, SessionState.proposed);
    expect(state.conversation('c-1045')!.messages.length, before + 3);

    state.dispose();
  });

  testWidgets('a session answer is final and shows on the card',
      (WidgetTester tester) async {
    final AppState state = AppState();
    const String id = 'm-session-c-1045';

    ChatMessage card(Conversation c) =>
        c.messages.firstWhere((ChatMessage m) => m.id == id);

    state.answerSession('c-1045', id, SessionState.accepted);
    expect(
      card(state.conversation('c-1045')!).sessionState,
      SessionState.accepted,
    );

    // A second tap on Decline must not undo the first answer.
    state.answerSession('c-1045', id, SessionState.declined);
    expect(
      card(state.conversation('c-1045')!).sessionState,
      SessionState.accepted,
    );

    state.dispose();
  });

  testWidgets('calls record their length, or that they were missed',
      (WidgetTester tester) async {
    final AppState state = AppState();

    state.logCall(
      'c-1045',
      video: false,
      connected: true,
      duration: const Duration(minutes: 2, seconds: 14),
    );
    expect(
      state.conversation('c-1045')!.messages.last.text,
      'Voice call · 02:14',
    );

    state.logCall(
      'c-1045',
      video: true,
      connected: false,
      duration: Duration.zero,
    );
    expect(state.conversation('c-1045')!.messages.last.text, 'Missed call');
    expect(
      state.conversation('c-1045')!.messages.last.kind,
      MessageKind.call,
    );

    state.dispose();
  });

  testWidgets('a locked thread refuses every kind of send',
      (WidgetTester tester) async {
    final AppState state = AppState();
    final int before = state.conversation('c-1038')!.messages.length;

    state.sendMessage('c-1038', 'Are you there?');
    state.sendImage('c-1038', _redDot);
    state.sendVoice('c-1038', 4);
    state.proposeSession('c-1038', DateTime(2026, 11, 3, 16, 45));

    expect(state.conversation('c-1038')!.messages.length, before);
    state.dispose();
  });

  testWidgets('the scripted answer types first, then leaves my line Seen',
      (WidgetTester tester) async {
    final AppState state = AppState();
    final int before = state.conversation('c-1040')!.messages.length;

    state.sendMessage('c-1040', 'One more thing.');
    final Conversation afterSend = state.conversation('c-1040')!;
    expect(afterSend.messages.length, before + 1);
    expect(afterSend.seen(afterSend.messages[before]), isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    expect(state.isTyping('c-1040'), isTrue);

    await tester.pump(const Duration(milliseconds: 1200));
    final Conversation afterReply = state.conversation('c-1040')!;
    expect(state.isTyping('c-1040'), isFalse);
    expect(afterReply.messages.length, before + 2);
    expect(afterReply.messages.last.fromMe, isFalse);
    // "Seen" is the presence of this reply, not a second piece of state.
    expect(afterReply.seen(afterReply.messages[before]), isTrue);

    state.dispose();
  });

  testWidgets('an emoji is inserted at the caret and delivery reads Seen',
      (WidgetTester tester) async {
    final AppState state = AppState();
    await _pumpChat(tester, state, 'c-1041');

    // The sample conversation's last line from me is followed by Amara's, so
    // it is the one carrying "Seen".
    expect(find.text('07:41 · Seen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'See you ');
    await tester.pump();
    await tester.tap(find.byTooltip('Insert an emoji'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('😀'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close the emoji panel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('See you 😀'), findsOneWidget);
    expect(state.conversation('c-1041')!.messages.length, 4);
  });

  testWidgets('a sample photo opens full screen and closes again',
      (WidgetTester tester) async {
    final AppState state = AppState();
    await _pumpChat(tester, state, 'c-1045');

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('Close the photo'), findsOneWidget);

    await tester.tap(find.byTooltip('Close the photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a pending thread has no field and no call buttons',
      (WidgetTester tester) async {
    final AppState state = AppState();
    await _pumpChat(tester, state, 'c-1038', size: const Size(390, 844));

    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Start a voice call'), findsNothing);
    expect(find.byTooltip('Start a video call'), findsNothing);
    expect(find.textContaining('Waiting for Liang to accept'), findsOneWidget);
  });
}
