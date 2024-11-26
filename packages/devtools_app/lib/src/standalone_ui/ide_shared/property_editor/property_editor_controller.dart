// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../../service/editor/api_classes.dart';
import '../../../service/editor/editor_client.dart';

final _log = Logger('property_editor_controller');

class PropertyEditorController extends DisposableController
    with AutoDisposeControllerMixin {
  PropertyEditorController(this.editorClient) {
    _log.info('Init property editor controller');
    _init();
  }

  final EditorClient editorClient;

  TextDocument? _currentDocument;
  CursorPosition? _currentCursorPosition;

  ValueListenable<List<EditableArgument>> get editableArgs => _editableArgs;
  final _editableArgs = ListValueNotifier<EditableArgument>([]);

  void _init() {
    editorClient.activeLocationChangedEventListenable.addListener(() async {
      final event = editorClient.activeLocationChangedEvent.value;
      if (event != null) {
        final textDocument = event.textDocument;
        final cursorPosition = event.selections.first.active;
        if (textDocument == _currentDocument &&
            cursorPosition == _currentCursorPosition) {
          return;
        }
        _currentDocument = textDocument;
        _currentCursorPosition = cursorPosition;
        final result = await editorClient.getEditableArguments(
          textDocument: textDocument,
          position: cursorPosition,
        );

        final args = result?.args ?? <EditableArgument>[];
        if (args.isNotEmpty) {
          _editableArgs.replaceAll(args);
        }
      }
    });
  }
}
