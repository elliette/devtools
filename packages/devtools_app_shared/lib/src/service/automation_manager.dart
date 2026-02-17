// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// TODO(elliiottbrooks): This is very hacky, should not be committed. Just for demo purposes.
class AutomationManager {
  AutomationManager() {
    print('automation manager created');
  }

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
      print('adding $key');
      final id = _generateId();
      _visibleKeys.putIfAbsent(id, () => key);
    }
    print('visibleKeys: $_visibleKeys');
  }

  void clearVisibleKeys() {
    print('clearing visible keys');
    _visibleKeys.clear();
  }

  final _visibleKeys = <String, Key>{};

  List<String> getVisibleWidgets() {
    print('CALLING GET VISIBLE WIDGETS');
    print('.  visible widgets: $_visibleKeys');
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

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
