// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_extensions/api.dart';
import 'package:devtools_shared/devtools_extensions.dart';

import '_controller_desktop.dart'
    if (dart.library.js_interop) '_controller_web.dart';

EmbeddedExtensionControllerImpl createEmbeddedExtensionController(
  DevToolsExtensionConfig config,
) {
  return EmbeddedExtensionControllerImpl(config);
}

abstract class EmbeddedExtensionController extends DisposableController {
  EmbeddedExtensionController(this.extensionConfig);

  final DevToolsExtensionConfig extensionConfig;

  void postMessage(
    DevToolsExtensionEventType type, {
    Map<String, String> data = const <String, String>{},
  }) {}
}
