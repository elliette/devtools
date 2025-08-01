// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:vm_service/vm_service.dart';

import '../../shared/globals.dart';
import '../../shared/primitives/utils.dart';
import '../../shared/utils/utils.dart';
import 'network_controller.dart';

class NetworkService {
  NetworkController get networkController =>
      screenControllers.lookup<NetworkController>();

  /// Tracks the time (microseconds since epoch) that the HTTP profile was last
  /// retrieved for a given isolate ID.
  final lastHttpDataRefreshTimePerIsolate = <String, int>{};

  /// Updates the last Socket data refresh time to the current time.
  ///
  /// If [alreadyRecordingSocketData] is true, it's unclear when the last
  /// refresh time would have occurred, so the refresh time is not updated.
  /// Otherwise, [NetworkController.lastSocketDataRefreshMicros] is updated to
  /// the current timeline timestamp.
  ///
  /// Returns the current timeline timestamp.
  Future<int> updateLastSocketDataRefreshTime({
    bool alreadyRecordingSocketData = false,
  }) async {
    // Set the current timeline time as the time of the last refresh.
    final timestampObj = await serviceConnection.serviceManager.service!
        .getVMTimelineMicros();

    final timestamp = timestampObj.timestamp!;
    if (!alreadyRecordingSocketData) {
      // Only include Socket requests issued after the current time.
      networkController.lastSocketDataRefreshMicros = timestamp;
    }
    return timestamp;
  }

  /// Updates the last HTTP data refresh time to the current time.
  ///
  /// If [alreadyRecordingHttp] is true it's unclear when the last refresh time
  /// would have occurred, so the refresh time is not updated. Otherwise,
  /// [lastHttpDataRefreshTimePerIsolate] is updated to the current
  /// time.
  void updateLastHttpDataRefreshTime({bool alreadyRecordingHttp = false}) {
    if (!alreadyRecordingHttp) {
      for (final isolateId in lastHttpDataRefreshTimePerIsolate.keys.toList()) {
        // It's safe to use `DateTime.now()` here since we don't need to worry
        // about dropping data between the time the last profile was generated
        // by the target application and the time `DateTime.now()` is called
        // here.
        lastHttpDataRefreshTimePerIsolate[isolateId] =
            DateTime.now().microsecondsSinceEpoch;
      }
    }
  }

  /// Force refreshes the HTTP requests logged to the timeline as well as any
  /// recorded Socket traffic.
  ///
  /// This method calls [cancelledCallback] after each async gap to ensure that
  /// this operation has not been cancelled during the async gap.
  Future<void> refreshNetworkData({
    DebounceCancelledCallback? cancelledCallback,
  }) async {
    if (serviceConnection.serviceManager.service == null) return;
    try {
      final timestampObj = await serviceConnection.serviceManager.service!
          .getVMTimelineMicros();
      if (cancelledCallback?.call() ?? false) return;

      final timestamp = timestampObj.timestamp!;
      final sockets = await _refreshSockets();
      if (cancelledCallback?.call() ?? false) return;

      networkController.lastSocketDataRefreshMicros = timestamp;
      List<HttpProfileRequest>? httpRequests;
      httpRequests = await _refreshHttpProfile();
      if (cancelledCallback?.call() ?? false) return;

      networkController.processNetworkTraffic(
        sockets: sockets,
        httpRequests: httpRequests,
      );
    } on RPCError catch (e) {
      if (!e.isServiceDisposedError) {
        // Swallow exceptions related to trying to interact with an
        // already-disposed service connection. Otherwise, rethrow.
        rethrow;
      }
    }
  }

  Future<List<HttpProfileRequest>> _refreshHttpProfile() async {
    final service = serviceConnection.serviceManager.service;
    if (service == null) return [];

    final requests = <HttpProfileRequest>[];
    await service.forEachIsolate((isolate) async {
      final request = await service.getHttpProfileWrapper(
        isolate.id!,
        updatedSince: DateTime.fromMicrosecondsSinceEpoch(
          lastHttpDataRefreshTimePerIsolate.putIfAbsent(
            isolate.id!,
            // If a new isolate has spawned, request all HTTP requests from the
            // start of time when retrieving the first profile.
            () => 0,
          ),
        ),
      );
      requests.addAll(request.requests);
      // Update the last request time using the timestamp from the HTTP profile
      // instead of DateTime.now() to avoid missing events due to the delay
      // between the last profile creation in the target process and the call
      // to DateTime.now() here.
      lastHttpDataRefreshTimePerIsolate[isolate.id!] =
          request.timestamp.microsecondsSinceEpoch;
    });
    return requests;
  }

  Future<void> _clearHttpProfile() async {
    final service = serviceConnection.serviceManager.service;
    if (service == null) return;
    await service.forEachIsolate((isolate) async {
      final future = service.clearHttpProfileWrapper(isolate.id!);
      // The above call won't complete immediately if the isolate is paused, so
      // give up waiting after 500ms. However, the call will complete eventually
      // if the isolate is eventually resumed.
      // TODO(jacobr): detect whether the isolate is paused using the vm
      // service and handle this case gracefully rather than timing out.
      await timeout(future, 500);
    });
  }

  Future<List<SocketStatistic>> _refreshSockets() async {
    final service = serviceConnection.serviceManager.service;
    if (service == null) return [];
    final sockets = <SocketStatistic>[];
    await service.forEachIsolate((isolate) async {
      final socketProfile = await service.getSocketProfileWrapper(isolate.id!);
      sockets.addAll(socketProfile.sockets);
    });

    // TODO(https://github.com/flutter/devtools/issues/5057):
    // Filter lastrefreshMicros inside [service.getSocketProfile] instead.
    final lastSocketDataRefreshMicros =
        networkController.lastSocketDataRefreshMicros;
    return [
      ...sockets.where(
        (element) =>
            element.startTime > lastSocketDataRefreshMicros ||
            (element.endTime ?? 0) > lastSocketDataRefreshMicros ||
            (element.lastReadTime ?? 0) > lastSocketDataRefreshMicros ||
            (element.lastWriteTime ?? 0) > lastSocketDataRefreshMicros,
      ),
    ];
  }

  Future<void> _clearSocketProfile() async {
    final service = serviceConnection.serviceManager.service;
    if (service == null) return;
    await service.forEachIsolate((isolate) async {
      final isolateId = isolate.id!;
      final socketProfilingAvailable = await service
          .isSocketProfilingAvailableWrapper(isolateId);
      if (socketProfilingAvailable) {
        final future = service.clearSocketProfileWrapper(isolateId);
        // The above call won't complete immediately if the isolate is paused, so
        // give up waiting after 500ms. However, the call will complete eventually
        // if the isolate is eventually resumed.
        // TODO(jacobr): detect whether the isolate is paused using the vm
        // service and handle this case gracefully rather than timing out.
        await timeout(future, 500);
      }
    });
  }

  /// Enables or disables Socket profiling for all isolates.
  Future<void> toggleSocketProfiling(bool state) async {
    final service = serviceConnection.serviceManager.service;
    if (service == null) return;
    await service.forEachIsolate((isolate) async {
      final isolateId = isolate.id!;
      final socketProfilingAvailable = await service
          .isSocketProfilingAvailableWrapper(isolateId);
      if (socketProfilingAvailable) {
        final future = service.socketProfilingEnabledWrapper(isolateId, state);
        // The above call won't complete immediately if the isolate is paused, so
        // give up waiting after 500ms. However, the call will complete eventually
        // if the isolate is eventually resumed.
        // TODO(jacobr): detect whether the isolate is paused using the vm
        // service and handle this case gracefully rather than timing out.
        await timeout(future, 500);
      }
    });
  }

  Future<void> clearData() async {
    await updateLastSocketDataRefreshTime();
    updateLastHttpDataRefreshTime();
    await _clearSocketProfile();
    await _clearHttpProfile();
  }
}
