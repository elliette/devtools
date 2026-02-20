// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:screenshot/screenshot.dart';

/// TODO(elliiottbrooks): This is very hacky, should not be committed. Just for demo purposes.
class AutomationManager {

  final _screenIdToScreenshotController = <String, ScreenshotController>{};


  ScreenshotController getScreenshotControllerForScreen(String screenId) {
    if (_screenIdToScreenshotController.containsKey(screenId)) {
      print('returning existing screenshot controller for $screenId');
      return _screenIdToScreenshotController[screenId]!;
    } else {
      final screenshotController = ScreenshotController();
      _screenIdToScreenshotController[screenId] = screenshotController;
      print('created new screenshot controller for $screenId');
      return screenshotController;
    }
  }

  Stream<String> get switchToScreenBroadcastStream =>
      _switchToScreenBroadcastStreamController.stream;
  final _switchToScreenBroadcastStreamController =
      StreamController<String>.broadcast();

  void switchToScreen(String screenId) {
    _switchToScreenBroadcastStreamController.add(screenId);
  }

  Future<Uint8List?> captureScreenshot(String screenId) async {
    final rawImage = await getScreenshotControllerForScreen(screenId).capture();
    return rawImage;
  }

  ValueListenable<PublicDevToolsKey?> get highlightedWidget =>
      _highlightedWidget;
  final _highlightedWidget = ValueNotifier<PublicDevToolsKey?>(null);

  set visibleKeys(Map<String, List<PublicDevToolsKey>> keys) {
    _visibleKeys.clear();
    _visibleKeys.addAll(keys);
  }

  void clearVisibleKeys() {
    _visibleKeys.clear();
  }

  final _visibleKeys = <String, List<PublicDevToolsKey>>{};

  List<String> getVisibleWidgets(String screenId) {
    return _visibleKeys[screenId]?.map((k) => k.publicName).toList() ?? [];
  }

  void highlightWidget(String screenId, String keyName) {
    final keys = _visibleKeys[screenId];
    if (keys != null) {
      final key = keys.firstWhere((k) => k.publicName == keyName);
      _highlightedWidget.value = key;
    }
  }

  void clearHighlight() {
    _highlightedWidget.value = null;
  }
}

/// A key that exposes a [publicName] in addition to a [value].
class PublicDevToolsKey extends LocalKey {
  /// Creates a key that delegates its [operator==] to the given [value] and [publicName].
  const PublicDevToolsKey(this.value, this.publicName);

  /// The value of the key.
  final String value;

  /// The public name of the key.
  final String publicName;

  /// Returns the [publicName].
  String get name => publicName;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is PublicDevToolsKey &&
        other.value == value &&
        other.publicName == publicName;
  }

  @override
  int get hashCode => Object.hash(value, publicName);

  @override
  String toString() {
    return 'PublicDevToolsKey($value, $publicName)';
  }
}
