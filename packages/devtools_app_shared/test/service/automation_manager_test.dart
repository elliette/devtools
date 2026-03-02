// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutomationManager', () {
    late AutomationManager automationManager;

    setUp(() {
      automationManager = AutomationManager();
    });

    test('highlightWidget sets value', () {
      expect(automationManager.highlightedWidget.value, isNull);
      const keyName = 'testKey';
      const screenId = 'testScreen';
      final key = PublicDevToolsKey('testValue', keyName);
      automationManager.visibleKeys = {
        screenId: [key],
      };
      automationManager.highlightWidget(screenId, keyName);
      expect(automationManager.highlightedWidget.value, equals(key));
    });

    test('clearHighlight clears value', () {
      const keyName = 'testKey';
      const screenId = 'testScreen';
      final key = PublicDevToolsKey('testValue', keyName);
      automationManager.visibleKeys = {
        screenId: [key],
      };
      automationManager.highlightWidget(screenId, keyName);
      expect(automationManager.highlightedWidget.value, equals(key));
      automationManager.clearHighlight();
      expect(automationManager.highlightedWidget.value, isNull);
    });

    test('getPerformanceData returns data from provider', () async {
      expect(await automationManager.getPerformanceData(), isEmpty);

      automationManager.registerPerformanceDataProvider(({
        bool includePerfettoTrace = true,
        bool onlyJank = false,
      }) async {
        return {
          'includePerfettoTrace': includePerfettoTrace,
          'onlyJank': onlyJank,
        };
      });

      expect(
        await automationManager.getPerformanceData(),
        equals({'includePerfettoTrace': false, 'onlyJank': true}),
      );

      expect(
        await automationManager.getPerformanceData(includePerfettoTrace: true),
        equals({'includePerfettoTrace': true, 'onlyJank': true}),
      );

      expect(
        await automationManager.getPerformanceData(onlyJank: false),
        equals({'includePerfettoTrace': false, 'onlyJank': false}),
      );
    });
  });
}
