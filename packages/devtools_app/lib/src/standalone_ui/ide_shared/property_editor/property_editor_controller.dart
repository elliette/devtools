// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


import 'package:devtools_app_shared/utils.dart';
import 'package:logging/logging.dart';

import '../../../service/editor/editor_client.dart';

final _log = Logger('property_editor_controller');

class PropertyEditorController extends DisposableController
    with AutoDisposeControllerMixin {
  PropertyEditorController(this.editorClient) {
    _log.info('Init property editor controller');
    _init();
  }

  final EditorClient editorClient;

  void _init() {
    editorClient.activeLocationChangedEventListenable.addListener(() async {
      final event = editorClient.activeLocationChangedEvent.value;
      if (event != null) {
        _log.info('got an active location changed event!');
        _log.info(event.selections);
        _log.info(event.textDocument);
      }
    });
  }
}
