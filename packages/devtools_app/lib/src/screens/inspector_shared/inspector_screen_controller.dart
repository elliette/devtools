// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app_shared/utils.dart';

import '../../shared/analytics/metrics.dart';
import '../../shared/console/primitives/simple_items.dart';
import '../inspector/inspector_controller.dart' as legacy;
import '../inspector/inspector_tree_controller.dart' as legacy;
import '../inspector_v2/inspector_controller.dart' as v2;
import '../inspector_v2/inspector_tree_controller.dart' as v2;

class InspectorScreenController extends DisposableController {
  @override
  void dispose() {
    v2InspectorController.dispose();
    legacyInspectorController.dispose();
    super.dispose();
  }

  final v2InspectorController = v2.InspectorController(
    inspectorTree: v2.InspectorTreeController(
      gaId: InspectorScreenMetrics.summaryTreeGaId,
    ),
    treeType: FlutterTreeType.widget,
  );

  final legacyInspectorController = legacy.InspectorController(
    inspectorTree: legacy.InspectorTreeController(
      gaId: InspectorScreenMetrics.summaryTreeGaId,
    ),
    detailsTree: legacy.InspectorTreeController(
      gaId: InspectorScreenMetrics.detailsTreeGaId,
    ),
    treeType: FlutterTreeType.widget,
  );
}

final _treeRefreshStopwatch = Stopwatch();
final _updateRowsStopwatch = Stopwatch();

bool? _updateRowsStarted = null;
bool? _updateRowsEnded = null;

void startTreeRefreshTimer() {
  _updateRowsStarted = null;
  _updateRowsEnded = null;

  // print('--- start refresh timer');
  _treeRefreshStopwatch
    ..stop()
    ..reset()
    ..start();
}

void startUpdateRowsTimer() {
  //  print('--- start update rows timer');
  _updateRowsStopwatch
    ..stop()
    ..reset()
    ..start();

  _updateRowsStarted = true;
}

void stopTreeRefreshTimer({isLegacy = false}) {
  // print('Update rows started: ${_updateRowsStarted}');
//   print('Update rows ended: ${_updateRowsEnded}');

  if (_updateRowsStarted == null) return;
  if (_updateRowsEnded == null) return;

  print(
      '[${isLegacy ? 'Legacy' : 'V2'} Inspector] Tree refresh: ${_treeRefreshStopwatch.elapsedMilliseconds} ms');
  _treeRefreshStopwatch
    ..stop()
    ..reset();
}

void stopUpdateRowsTimer({isLegacy = false}) {
  _updateRowsEnded = true;
  print(
      '[${isLegacy ? 'Legacy' : 'V2'} Inspector] Update rows: ${_updateRowsStopwatch.elapsedMilliseconds} ms');
  _updateRowsStopwatch
    ..stop()
    ..reset();
}
