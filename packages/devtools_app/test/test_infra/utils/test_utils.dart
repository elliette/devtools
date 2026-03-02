// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devtools_app/devtools_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a [FlutterTimelineEvent] for testing that mocks the
/// contained [PerfettoTrackEvent]s.
FlutterTimelineEvent testTimelineEvent({
  required String name,
  required TimelineEventType type,
  required int startMicros,
  required int endMicros,
  required Map<String, Object?> args,
  required Map<String, Object?> endArgs,
}) {
  final firstTrackEvent = PerfettoTrackEvent.test(
    name: name,
    type: PerfettoEventType.sliceBegin,
    timestampMicros: startMicros,
    args: args,
  );
  // Manually set the inferred type since extracting it from args/name happens
  // in the constructor only if we pass the real event, but we are passing dummy event.
  // Wait, my `PerfettoTrackEvent.test` sets `this.type` passed in argument.
  // But `timelineEventType` (Mutable? No, it's a field in `PerfettoTrackEvent` but it is not final in my Refactor?
  // Let's check `PerfettoTrackEvent` definition again.
  // `TimelineEventType? timelineEventType;` is a public field? Yes.
  // So I can set it.
  firstTrackEvent.timelineEventType = type;

  final endTrackEvent = PerfettoTrackEvent.test(
    name: name,
    type: PerfettoEventType.sliceEnd,
    timestampMicros: endMicros,
    args: endArgs,
  );
  endTrackEvent.timelineEventType = type;

  return FlutterTimelineEvent(firstTrackEvent)..addEndTrackEvent(endTrackEvent);

}

/// Overrides the system's clipboard behaviour so that strings sent to the
/// clipboard are instead passed to [clipboardContentsCallback]
///
/// [clipboardContentsCallback]  when Clipboard.setData is triggered, the text
/// contents will be passed to [clipboardContentsCallback]
void setupClipboardCopyListener({
  required void Function(String?) clipboardContentsCallback,
}) {
  // This intercepts the Clipboard.setData SystemChannel message,
  // and stores the contents that were (attempted) to be copied.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardContentsCallback((call.arguments as Map)['text']);
            break;
          case 'Clipboard.getData':
            return Future.value(<String, Object?>{});
          case 'Clipboard.hasStrings':
            return Future.value(<String, Object?>{'value': true});
          default:
            break;
        }

        return Future.value(true);
      });
}

Future<String> loadPageHtmlContent(String url) async {
  final request = await HttpClient().getUrl(Uri.parse(url));
  final response = await request.close();

  final completer = Completer<String>();
  final content = StringBuffer();
  response.transform(utf8.decoder).listen((data) {
    content.write(data);
  }, onDone: () => completer.complete(content.toString()));
  await completer.future;
  return content.toString();
}

void setCharacterWidthForTables() {
  // Modify the character width that will be used to calculate column sizes
  // in the tree table. The flutter_tester device uses a redacted font.
  setAssumedMonospaceCharacterWidth(16.0);
}

T getWidgetFromFinder<T>(Finder finder) =>
    finder.first.evaluate().first.widget as T;
