// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:io';

import 'package:devtools_app/devtools_app.dart';
import 'package:devtools_app/src/shared/framework/screen.dart';
import 'package:devtools_app/src/shared/framework/screen_controllers.dart';
import 'package:devtools_app/src/shared/framework/framework_controller.dart';
import 'package:devtools_app/src/shared/managers/survey.dart';
import 'package:devtools_app/src/extensions/extension_service.dart';
import 'package:devtools_app/src/shared/managers/script_manager.dart';
import 'package:devtools_app/src/screens/debugger/breakpoint_manager.dart';
import 'package:devtools_app/src/shared/console/eval/eval_service.dart';
import 'package:devtools_app/src/shared/preferences/preferences.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/shared.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_shared/devtools_extensions.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:devtools_test/devtools_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

void main() {
  late MockServiceConnectionManager mockServiceConnection;
  late MockAutomationManager mockAutomationManager;
  late TestExtensionService mockExtensionService;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {
      stderr.writeln(message);
    };

    mockServiceConnection = createMockServiceConnectionWithDefaults();
    final mockServiceManager =
        mockServiceConnection.serviceManager as MockServiceManager;
    when(mockServiceManager.service).thenReturn(null);
    when(mockServiceManager.connectedAppInitialized).thenReturn(false);
    when(mockServiceManager.manuallyDisconnect()).thenAnswer((_) async {});

    // reset connected state to false for the test
    (mockServiceManager.connectedState as ValueNotifier<ConnectedState>).value =
        const ConnectedState(false);

    final mockErrorBadgeManager = MockErrorBadgeManager();
    when(
      mockServiceConnection.errorBadgeManager,
    ).thenReturn(mockErrorBadgeManager);
    when(
      mockErrorBadgeManager.errorCountNotifier(any),
    ).thenReturn(ValueNotifier<int>(0));

    mockAutomationManager = MockAutomationManager();

    mockExtensionService = TestExtensionService();

    setGlobal(ServiceConnectionManager, mockServiceConnection);
    setGlobal(FrameworkController, FrameworkController());
    setGlobal(SurveyService, SurveyService());
    setGlobal(IdeTheme, IdeTheme());
    setGlobal(NotificationService, NotificationService());
    setGlobal(BannerMessagesController, BannerMessagesController());
    setGlobal(AutomationManager, mockAutomationManager);
    setGlobal(ExtensionService, mockExtensionService);
    setGlobal(ScreenControllers, ScreenControllers());
    setGlobal(OfflineDataController, OfflineDataController());
    setGlobal(MessageBus, MessageBus());
    setGlobal(ScriptManager, ScriptManager());
    setGlobal(BreakpointManager, BreakpointManager());
    setGlobal(EvalService, EvalService());
    setGlobal(DTDManager, DTDManager());
    setGlobal(PreferencesController, PreferencesController());
  });

  group('DevToolsApp visible keys', () {
    testWidgets('updates visible keys on connection change', (
      WidgetTester tester,
    ) async {
      stderr.writeln('Test started');

      final analyticsController = AnalyticsController(
        enabled: false,
        shouldShowConsentMessage: false,
        consentMessage: 'fake message',
      );

      final releaseNotesOnly = ReleaseNotesController();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<AnalyticsController>.value(value: analyticsController),
              Provider<ReleaseNotesController>.value(value: releaseNotesOnly),
            ],
            child: DevToolsApp(
              [DevToolsScreen<DevToolsScreenController>(_screen1)],
              analyticsController,
              key: const Key('app'),
            ),
          ),
        ),
      );

      stderr.writeln('Pumped widget');

      expect(find.byKey(const Key('app')), findsOneWidget);
      stderr.writeln('DevToolsApp found in widget tree');

      // Verify initial update in initState
      verify(mockAutomationManager.visibleKeys = any).called(1);
      stderr.writeln('Initial verification passed');

      // Simulate connection change
      final connectedStateNotifier =
          mockServiceConnection.serviceManager.connectedState;
      (connectedStateNotifier as ValueNotifier<ConnectedState>).value =
          const ConnectedState(true);
      await tester.pump();
      stderr.writeln('Connection state changed and pumped');

      // Verify update on connection change
      verify(mockAutomationManager.visibleKeys = any).called(1);
      stderr.writeln('Second verification passed');
    }, semanticsEnabled: false);
  });
}

class MockAutomationManager extends Mock implements AutomationManager {
  @override
  set visibleKeys(Map<String, List<PublicDevToolsKey>>? keys) {
    stderr.writeln('MockAutomationManager.visibleKeys set: $keys');
    super.noSuchMethod(
      Invocation.setter(#visibleKeys, keys),
      returnValueForMissingStub: null,
    );
  }
}

class TestExtensionService extends Fake implements ExtensionService {
  @override
  final ValueNotifier<DevToolsExtensionsGroup> currentExtensions =
      ValueNotifier((
        availableExtensions: <DevToolsExtensionConfig>[],
        visibleExtensions: <DevToolsExtensionConfig>[],
      ));

  @override
  final List<DevToolsExtensionConfig> visibleExtensions =
      <DevToolsExtensionConfig>[];

  @override
  final ValueNotifier<bool> refreshInProgress = ValueNotifier(false);
}

class _TestScreen extends Screen {
  const _TestScreen(
    this.name,
    this.key, {
    bool showFloatingDebuggerControls = true,
    Key? tabKey,
  }) : super(
         name,
         title: name,
         icon: Icons.computer,
         tabKey: tabKey,
         showFloatingDebuggerControls: showFloatingDebuggerControls,
       );

  final String name;
  final Key key;

  @override
  Widget buildScreenBody(BuildContext context) {
    return SizedBox(key: key);
  }
}

const _k1 = Key('body key 1');
const _t1 = Key('tab key 1');
const _screen1 = _TestScreen('screen1', _k1, tabKey: _t1);
