// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app/src/shared/development_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug flags are false', () {
    expect(debugDtdUri, isNull);
    expect(debugSendAnalytics, isFalse);
    expect(debugShowAnalyticsConsentMessage, isFalse);
    expect(debugDevToolsExtensions, isFalse);
    expect(debugSurvey, isFalse);
    expect(debugPerfettoTraceProcessing, isFalse);
    expect(debugTimers, isFalse);
  });
}
