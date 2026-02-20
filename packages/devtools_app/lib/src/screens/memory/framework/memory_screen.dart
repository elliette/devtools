// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/shared.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/analytics/analytics.dart' as ga;
import '../../../shared/framework/screen.dart';
import '../../../shared/primitives/listenable.dart';
import '../panes/diff/controller/diff_pane_controller.dart';
import '../panes/diff/diff_pane.dart';
import 'screen_body.dart';

class MemoryScreen extends Screen {
  MemoryScreen() : super.fromMetaData(ScreenMetaData.memory);

  static final id = ScreenMetaData.memory.id;

  static const memoryControlsKey = PublicDevToolsKey(
    'memoryControlsKey',
    'Memory Controls',
  );
  static const memoryRecordingButtonKey = PublicDevToolsKey(
    'memoryRecordingButtonKey',
    'Memory Recording Button',
  );
  static const memoryClearButtonKey = PublicDevToolsKey(
    'memoryClearButtonKey',
    'Memory Clear Button',
  );
  static const memoryChartKey = PublicDevToolsKey(
    'memoryChartKey',
    'Memory Chart',
  );
  static const memoryTabViewKey = PublicDevToolsKey(
    'memoryTabViewKey',
    'Memory Tab View',
  );
  static const memoryProfilePaneKey = PublicDevToolsKey(
    'memoryProfilePaneKey',
    'Memory Profile Pane',
  );
  static const memoryDiffPaneKey = PublicDevToolsKey(
    'memoryDiffPaneKey',
    'Memory Diff Pane',
  );
  static const memoryTracingPaneKey = PublicDevToolsKey(
    'memoryTracingPaneKey',
    'Memory Tracing Pane',
  );
  static const memoryLeaksPaneKey = PublicDevToolsKey(
    'memoryLeaksPaneKey',
    'Memory Leaks Pane',
  );
  static const memorySearchFieldKey = PublicDevToolsKey(
    'memorySearchFieldKey',
    'Memory Search Field',
  );

  @override
  List<PublicDevToolsKey> get keys => [
    memoryControlsKey,
    memoryRecordingButtonKey,
    memoryClearButtonKey,
    memoryChartKey,
    memoryTabViewKey,
    memoryProfilePaneKey,
    memoryDiffPaneKey,
    memoryTracingPaneKey,
    memoryLeaksPaneKey,
    memorySearchFieldKey,
  ];

  @override
  ValueListenable<bool> get showIsolateSelector =>
      const FixedValueListenable<bool>(true);

  @override
  String get docPageId => id;

  @override
  Widget buildScreenBody(BuildContext context) => const MemoryScreenBody();

  @override
  Widget? buildDisconnectedScreenBody(BuildContext context) {
    return const DisconnectedMemoryScreenBody();
  }

  // TODO(polina-c): when embedded and VSCode console features are implemented,
  // should be in native console in VSCode
  @override
  bool showConsole(EmbedMode embedMode) => true;
}

class MemoryScreenBody extends StatefulWidget {
  const MemoryScreenBody({super.key});

  @override
  MemoryScreenBodyState createState() => MemoryScreenBodyState();
}

class MemoryScreenBodyState extends State<MemoryScreenBody> {
  @override
  void initState() {
    super.initState();
    ga.screen(MemoryScreen.id);
  }

  @override
  Widget build(BuildContext context) {
    return const ConnectedMemoryBody();
  }
}

class DisconnectedMemoryScreenBody extends StatefulWidget {
  const DisconnectedMemoryScreenBody({super.key});

  @override
  State<DisconnectedMemoryScreenBody> createState() =>
      _DisconnectedMemoryScreenBodyState();
}

class _DisconnectedMemoryScreenBodyState
    extends State<DisconnectedMemoryScreenBody> {
  final diffController = DiffPaneController(loader: null, rootPackage: null);

  @override
  void initState() {
    super.initState();
    // TODO(kenz): we may want to differentiate this from connected memory
    // screen usage for analytics.
    ga.screen(MemoryScreen.id);
  }

  @override
  void dispose() {
    diffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoundedOutlinedBorder(
      clip: true,
      child: Column(
        children: [
          const AreaPaneHeader(
            title: Text('Diff Snapshots'),
            roundedTopBorder: false,
            includeTopBorder: false,
          ),
          Expanded(child: DiffPane(diffController: diffController)),
        ],
      ),
    );
  }
}
