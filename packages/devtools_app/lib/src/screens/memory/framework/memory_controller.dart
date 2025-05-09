// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

/// @docImport 'memory_tabs.dart';
library;

import 'dart:async';

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/feature_flags.dart';
import '../../../shared/framework/screen.dart';
import '../../../shared/framework/screen_controllers.dart';
import '../../../shared/globals.dart';
import '../../../shared/memory/class_name.dart';
import '../../../shared/memory/heap_graph_loader.dart';
import '../../../shared/offline/offline_data.dart';
import '../panes/chart/controller/chart_data.dart';
import '../panes/chart/controller/chart_pane_controller.dart';
import '../panes/diff/controller/diff_pane_controller.dart';
import '../panes/profile/profile_pane_controller.dart';
import '../panes/tracing/tracing_pane_controller.dart';
import 'offline_data/offline_data.dart';

/// Screen controller for the Memory screen.
///
/// This controller can be accessed from anywhere in DevTools, as long as it was
/// first registered, by calling `screenControllers.lookup<MemoryController>()`.
///
/// The controller lifecycle is managed by the [ScreenControllers] class. The
/// `init` method is called lazily upon the first controller access from
/// `screenControllers`. The `dispose` method is called by `screenControllers`
/// when DevTools is destroying a set of DevTools screen controllers.
///
/// This class must not have direct dependencies on web-only libraries. This
/// allows tests of the complicated logic in this class to run on the VM.
class MemoryController extends DevToolsScreenController
    with
        AutoDisposeControllerMixin,
        OfflineScreenControllerMixin<OfflineMemoryData> {
  @override
  final screenId = ScreenMetaData.memory.id;

  Future<void> get initialized => _initialized.future;
  final _initialized = Completer<void>();

  /// Index of the selected feature tab.
  ///
  /// This value is used to set the initial tab selection of the
  /// [MemoryTabView]. This widget will be disposed and re-initialized on
  /// DevTools screen changes, so we must store this value in the controller
  /// instead of the widget state.
  int selectedFeatureTabIndex = 0;

  late final DiffPaneController diff;

  late final ProfilePaneController? profile;

  late final MemoryChartPaneController chart;

  late final TracePaneController? trace;

  @override
  void init({
    @visibleForTesting DiffPaneController? connectedDiff,
    @visibleForTesting ProfilePaneController? connectedProfile,
  }) {
    super.init();
    unawaited(
      _init(connectedDiff: connectedDiff, connectedProfile: connectedProfile),
    );
  }

  @override
  void dispose() {
    HeapClassName.dispose();
    diff.dispose();
    profile?.dispose();
    chart.dispose();
    trace?.dispose();
    _gcing.dispose();
    super.dispose();
  }

  static const _dataKey = 'data';

  Future<void> _init({
    @visibleForTesting DiffPaneController? connectedDiff,
    @visibleForTesting ProfilePaneController? connectedProfile,
  }) async {
    if (_initialized.isCompleted) return;
    if (offlineDataController.showingOfflineData.value) {
      assert(connectedDiff == null && connectedProfile == null);
      await maybeLoadOfflineData(
        ScreenMetaData.memory.id,
        createData: createOfflineData,
        shouldLoad: (data) => true,
        loadData: (data) => _initializeData(offlineData: data),
      );
    } else {
      await serviceConnection.serviceManager.onServiceAvailable;
      _initializeData(
        diffPaneController: connectedDiff,
        profilePaneController: connectedProfile,
      );
    }
    assert(_initialized.isCompleted);
    assert(profile == null || profile!.rootPackage == diff.core.rootPackage);
  }

  @visibleForTesting
  static OfflineMemoryData createOfflineData(Map<String, Object?> json) {
    final data = json[_dataKey];
    if (data is OfflineMemoryData) return data;
    return OfflineMemoryData.fromJson(data as Map<String, Object?>);
  }

  void _initializeData({
    OfflineMemoryData? offlineData,
    @visibleForTesting DiffPaneController? diffPaneController,
    @visibleForTesting ProfilePaneController? profilePaneController,
  }) {
    assert(!_initialized.isCompleted);

    final isConnected =
        serviceConnection.serviceManager.connectedState.value.connected;

    chart = MemoryChartPaneController(data: offlineData?.chart ?? ChartData());

    final rootPackage = isConnected
        ? serviceConnection.serviceManager.rootInfoNow().package!
        : null;

    diff =
        diffPaneController ??
        offlineData?.diff ??
        DiffPaneController(
          loader: isConnected
              ? HeapGraphLoaderRuntime(chart.data.timeline)
              : null,
          rootPackage: rootPackage,
        );

    profile =
        profilePaneController ??
        offlineData?.profile ??
        ProfilePaneController(rootPackage: rootPackage!);

    trace = offlineData?.trace ?? TracePaneController(rootPackage: rootPackage);

    selectedFeatureTabIndex =
        offlineData?.selectedTab ?? selectedFeatureTabIndex;

    if (offlineData != null) {
      profile?.setFilter(offlineData.filter);
    }
    _shareClassFilterBetweenProfileAndDiff();

    _initialized.complete();
  }

  @override
  OfflineScreenData prepareOfflineScreenData() {
    return OfflineScreenData(
      screenId: ScreenMetaData.memory.id,
      data: {
        // Passing serializable data without conversion to json here
        // to skip serialization when data is passed in-process.
        _dataKey: OfflineMemoryData(
          diff,
          profile,
          chart.data,
          trace,
          diff.core.classFilter.value,
          selectedTab: selectedFeatureTabIndex,
        ),
      },
    );
  }

  void _shareClassFilterBetweenProfileAndDiff() {
    final theProfile = profile!;
    diff.derived.applyFilter(theProfile.classFilter.value);

    theProfile.classFilter.addListener(() {
      diff.derived.applyFilter(theProfile.classFilter.value);
    });

    diff.core.classFilter.addListener(() {
      theProfile.setFilter(diff.core.classFilter.value);
    });
  }

  ValueListenable<bool> get isGcing => _gcing;
  final _gcing = ValueNotifier<bool>(false);

  Future<void> gc() async {
    _gcing.value = true;
    try {
      await serviceConnection.serviceManager.service!.getAllocationProfile(
        (serviceConnection
            .serviceManager
            .isolateManager
            .selectedIsolate
            .value
            ?.id)!,
        gc: true,
      );
      chart.data.timeline.addGCEvent();
      notificationService.push('Successfully garbage collected.');
    } finally {
      _gcing.value = false;
    }
  }

  @override
  FutureOr<void> releaseMemory({bool partial = false}) async {
    if (FeatureFlags.memoryObserver) {
      diff.clearSnapshots(partial: partial);
      // Clear all allocation traces since the traces form a single tracing
      // profile.
      await trace?.clear();
    }
  }
}
