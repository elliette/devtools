// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutomationManager', () {
    late AutomationManager automationManager;

    setUp(() {
      automationManager = AutomationManager();
    });

    test('highlightWidget sets value', () {
      expect(automationManager.highlightedWidget.value, isNull);
      final key = UniqueKey();
      automationManager.highlightWidget(key);
      expect(automationManager.highlightedWidget.value, equals(key));
    });

    test('clearHighlight clears value', () {
      final key = UniqueKey();
      automationManager.highlightWidget(key);
      expect(automationManager.highlightedWidget.value, equals(key));
      automationManager.clearHighlight();
      expect(automationManager.highlightedWidget.value, isNull);
    });
  });
}
