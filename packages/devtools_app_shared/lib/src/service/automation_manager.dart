// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:screenshot/screenshot.dart';

/// TODO(elliiottbrooks): This is very hacky, should not be committed. Just for demo purposes.
class AutomationManager {
  AutomationManager() {
    screenshotController = ScreenshotController();
  }

  late ScreenshotController screenshotController;

  Stream<String> get switchToScreenBroadcastStream =>
      _switchToScreenBroadcastStreamController.stream;
  final _switchToScreenBroadcastStreamController =
      StreamController<String>.broadcast();

  //   Stream<String> get captureScreenshotBroadcastStream =>
  //     _captureScreenshotBroadcastStreamController.stream;
  // final _captureScreenshotBroadcastStreamController =
  //     StreamController<String>.broadcast();

  void switchToScreen(String screenId) {
    _switchToScreenBroadcastStreamController.add(screenId);
  }

  Future<Uint8List?> captureScreenshot() async {
    final rawImage = await screenshotController.capture();
    return rawImage;
  }

  ValueListenable<Key?> get highlightedWidget => _highlightedWidget;
  final _highlightedWidget = ValueNotifier<Key?>(null);

  set visibleKeys(List<Key> keys) {
    for (final key in keys) {
      final id = _generateId();
      _visibleKeys.putIfAbsent(id, () => key);
    }
  }

  void clearVisibleKeys() {
    _visibleKeys.clear();
  }

  final _visibleKeys = <String, Key>{};

  List<String> getVisibleWidgets() {
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
