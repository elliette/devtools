// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app/devtools_app.dart';
import 'package:devtools_app/src/service/editor/api_classes.dart';
import 'package:devtools_app/src/standalone_ui/ide_shared/property_editor/property_editor_controller.dart';
import 'package:devtools_app/src/standalone_ui/ide_shared/property_editor/property_editor_view.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_test/devtools_test.dart';
import 'package:devtools_test/helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

typedef Location = ({TextDocument document, CursorPosition position});
typedef LocationToArgsResult = Map<Location, EditableArgumentsResult>;

void main() {
  final eventController = StreamController<ActiveLocationChangedEvent>();
  final eventStream = eventController.stream;

  final LocationToArgsResult locationToArgsResult = {
    (document: textDocument1, position: activeCursorPosition1): result1,
    (document: textDocument2, position: activeCursorPosition2): result2,
  };

  late MockEditorClient mockEditorClient;
  late PropertyEditorController controller;
  late PropertyEditorView propertyEditor;

  setUpAll(() {
    setGlobal(ServiceConnectionManager, FakeServiceConnectionManager());
    setGlobal(IdeTheme, IdeTheme());

    mockEditorClient = MockEditorClient();
    when(
      mockEditorClient.activeLocationChangedStream,
    ).thenAnswer((_) => eventStream);

    controller = PropertyEditorController(mockEditorClient);
    propertyEditor = PropertyEditorView(controller: controller);
  });

  group('on cursor location change', () {
    void Function()? listener;

    Future<List<EditableArgument>> waitForEditableArgs() {
      final argsCompleter = Completer<List<EditableArgument>>();
      listener = () {
        argsCompleter.complete(controller.editableArgs.value);
      };
      controller.editableArgs.addListener(listener!);
      return argsCompleter.future;
    }

    void verifyEditableArgs({
      required List<EditableArgument> actual,
      required List<EditableArgument> expected,
    }) {
      final actualArgNames = actual.map((arg) => arg.name).toList();
      final expectedArgNames = expected.map((arg) => arg.name).toList();

      expect(
        collectionEquals(actualArgNames, expectedArgNames),
        isTrue,
        reason:
            'Expected ${expectedArgNames.join(', ')} not ${actualArgNames.join(', ')}',
      );
    }

    setUp(() {
      for (final MapEntry(key: location, value: result)
          in locationToArgsResult.entries) {
        when(
          // ignore: discarded_futures, for mocking purposes.
          mockEditorClient.getEditableArguments(
            textDocument: location.document,
            position: location.position,
          ),
        ).thenAnswer((realInvocation) => Future.value(result));
      }
    });

    tearDown(() {
      if (listener != null) {
        controller.editableArgs.removeListener(listener!);
      }
    });

    testWidgets('verify editable arguments for first cursor location', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Load the property editor.
        await tester.pumpWidget(wrap(propertyEditor));
        final editableArgsFuture = waitForEditableArgs();

        // Send an active location changed event.
        eventController.add(activeLocationChangedEvent1);

        // Wait for the expected editable args.
        final editableArgs = await editableArgsFuture;
        verifyEditableArgs(actual: editableArgs, expected: result1.args);
      });
    });

    testWidgets('verify editable arguments for second cursor location', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Load the property editor.
        await tester.pumpWidget(wrap(propertyEditor));
        final editableArgsFuture = waitForEditableArgs();

        // Send an active location changed event.
        eventController.add(activeLocationChangedEvent2);

        // Wait for the expected editable args.
        final editableArgs = await editableArgsFuture;
        verifyEditableArgs(actual: editableArgs, expected: result2.args);
      });
    });
  });

  group('inputs for editable arguments', () {
    testWidgets('inputs are expected for first group of editable arguments', (
      tester,
    ) async {
      // Load the property editor.
      await tester.pumpWidget(wrap(propertyEditor));

      // Change the editable args.
      controller.updateEditableArgs(result1.args);
      await tester.pumpAndSettle();

      // Verify the inputs are expected.
      expect(_findNoPropertiesMessage, findsNothing);
      expect(_findTextFormField('title'), findsOneWidget);
      expect(_findTextFormField('width'), findsOneWidget);
      expect(_findTextFormField('height'), findsOneWidget);
    });

    testWidgets('inputs are expected for second group of editable arguments', (
      tester,
    ) async {
      // Load the property editor.
      await tester.pumpWidget(wrap(propertyEditor));

      // Change the editable args.
      controller.updateEditableArgs(result2.args);
      await tester.pumpAndSettle();

      // Verify the inputs are expected.
      expect(_findNoPropertiesMessage, findsNothing);
      final softWrapInput = _findDropdownButtonFormField('softWrap');
      expect(softWrapInput, findsOneWidget);
      final alignInput = _findDropdownButtonFormField('align');
      expect(alignInput, findsOneWidget);
    });

    testWidgets('softWrap input has expected options', (tester) async {
      // Load the property editor.
      await tester.pumpWidget(wrap(propertyEditor));

      // Change the editable args.
      controller.updateEditableArgs(result2.args);
      await tester.pumpAndSettle();

      // Verify the input options are expected.
      final softWrapInput = _findDropdownButtonFormField('softWrap');
      await _verifyDropdownMenuItems(
        softWrapInput,
        menuOptions: ['true', 'false'],
        selectedOption: 'true',
        tester: tester,
      );
    });

    testWidgets('align input has expected options', (tester) async {
      // Load the property editor.
      await tester.pumpWidget(wrap(propertyEditor));

      // Change the editable args.
      controller.updateEditableArgs(result2.args);
      await tester.pumpAndSettle();

      // Verify the input options are expected.
      final alignInput = _findDropdownButtonFormField('align');
      await _verifyDropdownMenuItems(
        alignInput,
        menuOptions: [
          'Alignment.bottomCenter',
          'Alignment.bottomLeft',
          'Alignment.bottomRight',
          'Alignment.center',
          'Alignment.centerLeft',
          'Alignment.centerRight',
          'Alignment.topCenter',
          'Alignment.topLeft',
          'Alignment.topRight',
        ],
        selectedOption: 'Alignment.center',
        tester: tester,
      );
    });
  });
}

final _findNoPropertiesMessage = find.text(
  'No widget properties at current cursor location.',
);

Finder _findTextFormField(String inputName) => find.ancestor(
  of: find.text(inputName),
  matching: find.byType(TextFormField),
);

Finder _findDropdownButtonFormField(String inputName) => find.ancestor(
  of: find.text(inputName),
  matching: find.byType(DropdownButtonFormField<String>),
);

Future<void> _verifyDropdownMenuItems(
  Finder dropdownButton, {
  required List<String> menuOptions,
  required String selectedOption,
  required WidgetTester tester,
}) async {
  // Click button to open the options.
  await tester.tap(dropdownButton);
  await tester.pumpAndSettle();

  // Verify the options are expected.
  for (final menuOptionValue in menuOptions) {
    final menuOptionFinder = find.ancestor(
      of: find.text(menuOptionValue),
      matching: find.byType(DropdownMenuItem<String>),
    );
    if (menuOptionValue == selectedOption) {
      // Flutter renders two menu options for the selected option.
      expect(menuOptionFinder, findsNWidgets(2));
    } else {
      expect(menuOptionFinder, findsOneWidget);
    }
  }
}

// Location position 1
final activeCursorPosition1 = CursorPosition(character: 10, line: 20);
final anchorCursorPosition1 = CursorPosition(character: 12, line: 7);
final editorSelection1 = EditorSelection(
  active: activeCursorPosition1,
  anchor: anchorCursorPosition1,
);
final textDocument1 = TextDocument(
  uriAsString: '/my/fake/file.dart',
  version: 1,
);
final activeLocationChangedEvent1 = ActiveLocationChangedEvent(
  selections: [editorSelection1],
  textDocument: textDocument1,
);

// Location position 2
final activeCursorPosition2 = CursorPosition(character: 18, line: 6);
final anchorCursorPosition2 = CursorPosition(character: 22, line: 9);
final editorSelection2 = EditorSelection(
  active: activeCursorPosition2,
  anchor: anchorCursorPosition2,
);
final textDocument2 = TextDocument(
  uriAsString: '/my/fake/other.dart',
  version: 1,
);
final activeLocationChangedEvent2 = ActiveLocationChangedEvent(
  selections: [editorSelection2],
  textDocument: textDocument2,
);

// Result 1
final titleProperty = EditableArgument(
  name: 'title',
  value: 'Hello world!',
  type: 'string',
  isDefault: false,
  isEditable: true,
  isNullable: false,
  isRequired: true,
  hasArgument: false,
);
final widthProperty = EditableArgument(
  name: 'width',
  displayValue: '100.0',
  type: 'double',
  isEditable: false,
  isDefault: false,
  errorText: 'Some reason for why this can\'t be edited.',
  isNullable: false,
  value: 20.0,
  isRequired: true,
  hasArgument: false,
);
final heightProperty = EditableArgument(
  name: 'height',
  type: 'double',
  hasArgument: false,
  isEditable: true,
  isNullable: false,
  value: 20.0,
  isDefault: true,
  isRequired: true,
);
final result1 = EditableArgumentsResult(
  args: [titleProperty, widthProperty, heightProperty],
);

// Result 2
final softWrapProperty = EditableArgument(
  name: 'softWrap',
  type: 'bool',
  isNullable: false,
  value: true,
  isDefault: true,
  hasArgument: false,
  isEditable: true,
  isRequired: false,
);
final alignProperty = EditableArgument(
  name: 'align',
  type: 'enum',
  isNullable: false,
  hasArgument: true,
  isDefault: false,
  isRequired: false,
  isEditable: true,
  value: 'Alignment.center',
  options: [
    'Alignment.bottomCenter',
    'Alignment.bottomLeft',
    'Alignment.bottomRight',
    'Alignment.center',
    'Alignment.centerLeft',
    'Alignment.centerRight',
    'Alignment.topCenter',
    'Alignment.topLeft',
    'Alignment.topRight',
  ],
);
final result2 = EditableArgumentsResult(
  args: [softWrapProperty, alignProperty],
);
