// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:math' as math;

import 'package:devtools_app_shared/service.dart' show FlutterEvent;
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';

import '../../../../../shared/globals.dart';
import '../../../../../shared/utils/utils.dart';
import '../../../shared/primitives/memory_timeline.dart';
import '../data/primitives.dart';

final _log = Logger('memory_protocol');

enum _ContinuesState { none, stop, next }

class MemoryTracker extends Disposable {
  MemoryTracker(this.timeline, {required this.isAndroidChartVisible});

  final MemoryTimeline timeline;

  final ValueListenable<bool> isAndroidChartVisible;

  _ContinuesState _monitorContinuesState = _ContinuesState.none;

  final _isolateHeaps = <String, MemoryUsage>{};

  /// Polled VM current RSS.
  int _processRss = 0;

  /// Polled adb dumpsys meminfo values.
  AdbMemoryInfo? _adbMemoryInfo;

  /// Polled engine's RasterCache estimates.
  RasterCache? rasterCache;

  Timer? _monitorContinues;

  void onGCEvent(Event event) {
    final newHeap = HeapSpace.parse(event.json!['new'])!;
    final oldHeap = HeapSpace.parse(event.json!['old'])!;

    final memoryUsage = MemoryUsage(
      externalUsage: newHeap.external! + oldHeap.external!,
      heapCapacity: newHeap.capacity! + oldHeap.capacity!,
      heapUsage: newHeap.used! + oldHeap.used!,
    );

    _updateGCEvent(event.isolate!.id!, memoryUsage);
  }

  void onMemoryData(Event data) {
    var extensionEventKind = data.extensionKind;
    String? customEventKind;
    if (MemoryTimeline.isCustomEvent(data.extensionKind!)) {
      extensionEventKind = MemoryTimeline.devToolsExtensionEvent;
      customEventKind = MemoryTimeline.customEventName(data.extensionKind!);
    }
    final jsonData = data.extensionData!.data.cast<String, Object>();
    switch (extensionEventKind) {
      case FlutterEvent.imageSizesForFrame:
        timeline.addExtensionEvent(
          data.timestamp,
          data.extensionKind,
          jsonData,
        );
        break;
      case MemoryTimeline.devToolsExtensionEvent:
        timeline.addExtensionEvent(
          data.timestamp,
          MemoryTimeline.customDevToolsEvent,
          jsonData,
          customEventName: customEventKind,
        );
        break;
    }
  }

  void onIsolateEvent(Event data) {
    if (data.kind == EventKind.kIsolateExit) {
      _isolateHeaps.remove(data.isolate!.id);
    }
  }

  Future<void> pollMemory() async {
    final isolateMemory = <IsolateRef, MemoryUsage>{};
    for (final isolateRef
        in serviceConnection.serviceManager.isolateManager.isolates.value) {
      try {
        isolateMemory[isolateRef] = await serviceConnection
            .serviceManager
            .service!
            .getMemoryUsage(isolateRef.id!);
      } on SentinelException {
        // Isolates can disappear during polling, so just swallow this exception.
      }
    }

    // Polls for current Android meminfo using:
    //    > adb shell dumpsys meminfo -d <package_name>
    _adbMemoryInfo =
        serviceConnection.serviceManager.connectedState.value.connected &&
            serviceConnection.serviceManager.vm!.operatingSystem == 'android' &&
            isAndroidChartVisible.value
        ? await _fetchAdbInfo()
        : AdbMemoryInfo.empty();

    // Query the engine's rasterCache estimate.
    rasterCache = await _fetchRasterCacheInfo();

    // Polls for current RSS size.
    final vm = await serviceConnection.serviceManager.service!.getVM();
    _update(vm, isolateMemory);
  }

  void _update(VM vm, Map<IsolateRef, MemoryUsage> isolateMemory) {
    _processRss = vm.json!['_currentRSS'];

    _isolateHeaps.clear();

    for (final isolateRef in isolateMemory.keys) {
      _isolateHeaps[isolateRef.id!] = isolateMemory[isolateRef]!;
    }

    _recalculate();
  }

  void _updateGCEvent(String isolateId, MemoryUsage memoryUsage) {
    _isolateHeaps[isolateId] = memoryUsage;
    _recalculate(fromGC: true);
  }

  /// Fetch the Flutter engine's Raster Cache metrics.
  ///
  /// Returns engine's rasterCache estimates or null.
  Future<RasterCache?> _fetchRasterCacheInfo() async {
    final response = await serviceConnection.rasterCacheMetrics;
    if (response == null) return null;
    final rasterCache = RasterCache.parse(response.json);
    return rasterCache;
  }

  /// Fetch ADB meminfo, ADB returns values in KB convert to total bytes.
  Future<AdbMemoryInfo> _fetchAdbInfo() async =>
      AdbMemoryInfo.fromJsonInKB((await serviceConnection.adbMemoryInfo).json!);

  void _recalculate({bool fromGC = false}) {
    int used = 0;
    int capacity = 0;
    int external = 0;

    final isolateCount = _isolateHeaps.length;
    final keys = _isolateHeaps.keys.toList();
    for (var index = 0; index < isolateCount; index++) {
      final isolateId = keys[index];
      final usage = _isolateHeaps[isolateId];
      if (usage != null) {
        // Isolate is live (a null usage implies sentinel).
        used += usage.heapUsage!;
        capacity += usage.heapCapacity!;
        external += usage.externalUsage!;
      }
    }

    int time = DateTime.now().millisecondsSinceEpoch;
    if (timeline.data.isNotEmpty) {
      time = math.max(time, timeline.data.last.timestamp);
    }

    // Process any memory events?
    final eventSample = _processEventSample(timeline, time);

    if (eventSample != null && eventSample.isEventAllocationAccumulator) {
      if (eventSample.allocationAccumulator!.isStart) {
        // Stop Continuous events being auto posted - a new start is beginning.
        _monitorContinuesState = _ContinuesState.stop;
      }
    } else if (_monitorContinuesState == _ContinuesState.next) {
      if (_monitorContinues != null) {
        _monitorContinues!.cancel();
        _monitorContinues = null;
      }
      _monitorContinues ??= Timer(
        const Duration(milliseconds: 300),
        _recalculate,
      );
    }

    final sample = HeapSample(
      time,
      _processRss,
      // Displaying capacity dashed line on top of stacked (used + external).
      capacity + external,
      used,
      external,
      fromGC,
      _adbMemoryInfo,
      eventSample,
      rasterCache,
    );

    timeline.addSample(sample);

    // Signal continues events are to be emitted.  These events are hidden
    // until a reset event then the continuous events between last monitor
    // start/reset and latest reset are made visible.
    if (eventSample != null &&
        eventSample.isEventAllocationAccumulator &&
        eventSample.allocationAccumulator!.isStart) {
      _monitorContinuesState = _ContinuesState.next;
    }
  }

  /// Many extension events could arrive between memory collection ticks, those
  /// events need to be associated with a particular memory tick (timestamp).
  ///
  /// This routine collects those new events received that are closest to a tick
  /// (time parameter)).
  ///
  /// Returns copy of events to associate with an existing HeapSample tick
  /// (contained in the EventSample). See [_processEventSample] it computes the
  /// events to aggregate to an existing HeapSample or delay associating those
  /// events until the next HeapSample (tick) received see [_recalculate].
  EventSample _pullClone(MemoryTimeline memoryTimeline, int time) {
    final pulledEvent = memoryTimeline.pullEventSample();
    final extensionEvents = memoryTimeline.extensionEvents;
    final eventSample = pulledEvent.clone(
      time,
      extensionEvents: extensionEvents,
    );
    if (extensionEvents?.isNotEmpty == true) {
      debugLogger('ExtensionEvents Received');
    }

    return eventSample;
  }

  EventSample? _processEventSample(MemoryTimeline memoryTimeline, int time) {
    if (memoryTimeline.anyEvents) {
      final eventTime = memoryTimeline.peekEventTimestamp;
      final timeDuration = Duration(milliseconds: time);
      final eventDuration = Duration(milliseconds: eventTime);

      final compared = timeDuration.compareTo(eventDuration);
      if (compared < 0) {
        // If the event is +/- _updateDelay (500 ms) of the current time then
        // associate the EventSample with the current HeapSample.
        if ((timeDuration + chartUpdateDelay).compareTo(eventDuration) >= 0) {
          // Currently, events are all UI events so duration < _updateDelay
          return _pullClone(memoryTimeline, time);
        }
        // Throw away event, missed attempt to attach to a HeapSample.
        final ignoreEvent = memoryTimeline.pullEventSample();
        _log.info(
          'Event duration is lagging ignore event'
          'timestamp: ${MemoryTimeline.fineGrainTimestampFormat(time)} '
          'event: ${MemoryTimeline.fineGrainTimestampFormat(eventTime)}'
          '\n$ignoreEvent',
        );
        return null;
      }

      if (compared > 0) {
        final msDiff = time - eventTime;
        if (msDiff > chartUpdateDelay.inMilliseconds) {
          // eventSample is in the future.
          if ((timeDuration - chartUpdateDelay).compareTo(eventDuration) >= 0) {
            // Able to match event time to a heap sample. We will attach the
            // EventSample to this HeapSample.
            return _pullClone(memoryTimeline, time);
          }
          // Keep the event, its time hasn't caught up to the HeapSample time yet.
          return null;
        }
        // The almost exact eventSample we have.
        return _pullClone(memoryTimeline, time);
      }
    }

    if (memoryTimeline.anyPendingExtensionEvents) {
      final extensionEvents = memoryTimeline.extensionEvents;
      return EventSample.extensionEvent(time, extensionEvents);
    }

    return null;
  }

  @override
  void dispose() {
    _monitorContinues?.cancel();
    _monitorContinues = null;
    super.dispose();
  }
}
