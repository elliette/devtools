// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';

import '../../../../../shared/globals.dart';
import 'chart_connection.dart';
import 'chart_data.dart';
import 'charts/android_chart_controller.dart';
import 'charts/event_chart_controller.dart';
import 'charts/vm_chart_controller.dart';

class MemoryChartPaneController extends DisposableController
    with AutoDisposeControllerMixin {
  MemoryChartPaneController({required this.data}) {
    init();
  }

  late final ChartData data;

  ChartVmConnection? _chartConnection;

  late final event = EventChartController(data.timeline, paused: paused);
  late final vm = VMChartController(data.timeline, paused: paused);
  late final android = AndroidChartController(
    data.timeline,
    sharedLabels: vm.labelTimestamps,
    paused: paused,
  );

  @override
  void init() {
    super.init();
    if (offlineDataController.showingOfflineData.value) {
      // Setting paused to false, because `recomputeChartData` is noop when it is true.
      _paused.value = false;
      recomputeChartData();
      _paused.value = true;
    }

    _maybeUpdateChart();
    addAutoDisposeListener(isChartVisible, _maybeUpdateChart);

    _maybeCalculateAndroidChartVisibility();
    addAutoDisposeListener(
      preferences.memory.androidCollectionEnabled,
      _maybeCalculateAndroidChartVisibility,
    );
  }

  void resetAll() {
    event.reset();
    vm.reset();
    android.reset();
  }

  /// Recomputes (attaches data to the chart) for either live or offline data
  /// source.
  void recomputeChartData() {
    resetAll();
    event.setupData();
    event.dirty = true;
    vm.setupData();
    vm.dirty = true;
    android.setupData();
    android.dirty = true;
  }

  ValueListenable<bool> get paused => _paused;
  final _paused = ValueNotifier<bool>(true);
  void pause() => _paused.value = true;
  void resume() => _paused.value = false;

  final isAndroidChartVisible = ValueNotifier<bool>(false);
  void _maybeCalculateAndroidChartVisibility() {
    if (!isChartVisible.value) return;
    assert(data.isDeviceAndroid != null || _chartConnection!.initialized);
    data.isDeviceAndroid ??= _chartConnection!.isDeviceAndroid;
    isAndroidChartVisible.value =
        data.isDeviceAndroid! &&
        preferences.memory.androidCollectionEnabled.value;
  }

  ValueListenable<bool> get isChartVisible => preferences.memory.showChart;

  void _maybeUpdateChart() {
    if (!isChartVisible.value) return;
    if (!offlineDataController.showingOfflineData.value) {
      if (_chartConnection == null) {
        _chartConnection ??= _chartConnection = ChartVmConnection(
          data.timeline,
          isAndroidChartVisible: isAndroidChartVisible,
        );
        if (serviceConnection.serviceManager.connectedState.value.connected) {
          _chartConnection!.init();
          resume();
        } else {
          data.isDeviceAndroid ??= false;
        }
      }
    }
    _maybeCalculateAndroidChartVisibility();
  }

  @override
  void dispose() {
    data.dispose();
    event.dispose();
    vm.dispose();
    android.dispose();
    _paused.dispose();
    isAndroidChartVisible.dispose();
    _chartConnection?.dispose();
    super.dispose();
  }
}
