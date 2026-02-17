// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// TODO(elliiottbrooks): This is very hacky, should not be committed. Just for demo purposes.
class AutomationManager {
  Stream<String> get switchToScreenBroadcastStream =>
      _switchToScreenBroadcastStreamController.stream;
  final _switchToScreenBroadcastStreamController =
      StreamController<String>.broadcast();

  void switchToScreen(String screenId) {
    _switchToScreenBroadcastStreamController.add(screenId);
  }

  ValueListenable<Key?> get highlightedWidget => _highlightedWidget;
  final _highlightedWidget = ValueNotifier<Key?>(null);

  set visibleKeys(List<Key> keys) {
    for (final key in keys) {
      _visibleKeys.putIfAbsent(key.toString(), () => key);
    }
  }

  final _visibleKeys = <String, Key>{};

  List<String> get visibleWidgetKeyIds {
    return _visibleKeys.keys.toList();
  }

  void highlightWidget(String keyId) {
    final key = _visibleKeys[keyId];
    if (key != null) {
      _highlightedWidget.value = key;
    }
  }

  void clearHighlight() {
    _highlightedWidget.value = null;
  }
}
