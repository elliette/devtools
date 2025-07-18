// Copyright 2018 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:core';

import 'package:devtools_shared/devtools_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart' hide Error;

import '../utils/auto_dispose.dart';
import 'connected_app.dart';
import 'constants.dart';
import 'isolate_manager.dart';
import 'rpc_error_extension.dart';
import 'service_extensions.dart' as extensions;
import 'service_utils.dart';

final _log = Logger('service_extension_manager');

/// Manager that handles tracking the service extension for the main isolate.
final class ServiceExtensionManager with DisposerMixin {
  ServiceExtensionManager(this._isolateManager);

  VmService? _service;

  bool _checkForFirstFrameStarted = false;

  final IsolateManager _isolateManager;

  Completer<void> _firstFrameReceived = Completer();

  bool get _firstFrameEventReceived => _firstFrameReceived.isCompleted;

  final _serviceExtensionAvailable = <String, ValueNotifier<bool>>{};

  final _serviceExtensionStates =
      <String, ValueNotifier<ServiceExtensionState>>{};

  /// All available service extensions.
  final _serviceExtensions = <String>{};

  /// All service extensions that are currently enabled.
  final _enabledServiceExtensions = <String, ServiceExtensionState>{};

  /// Map from service extension name to [Completer] that completes when the
  /// service extension is registered or the isolate shuts down.
  final _maybeRegisteringServiceExtensions = <String, Completer<bool>>{};

  /// Temporarily stores service extensions that we need to add. We should not
  /// add extensions until the first frame event has been received
  /// [_firstFrameEventReceived].
  final _pendingServiceExtensions = <String>{};

  Map<IsolateRef, List<AsyncCallback>> _callbacksOnIsolateResume = {};

  ConnectedApp get connectedApp => _connectedApp!;
  ConnectedApp? _connectedApp;

  Future<void> _handleIsolateEvent(Event event) async {
    if (event.kind == EventKind.kServiceExtensionAdded) {
      // On hot restart, service extensions are added from here.
      await _maybeAddServiceExtension(event.extensionRPC);
    }
  }

  Future<void> _handleExtensionEvent(Event event) async {
    switch (event.extensionKind) {
      case FlutterEvent.firstFrame:
      case FlutterEvent.frame:
        await _onFrameEventReceived();
        break;
      case FlutterEvent.serviceExtensionStateChanged:
        final name = event.rawExtensionData['extension'].toString();
        final encodedValue = event.rawExtensionData['value'].toString();
        await _updateServiceExtensionForStateChange(name, encodedValue);
        break;
      case DeveloperServiceEvent.httpTimelineLoggingStateChange:
        final name = extensions.httpEnableTimelineLogging.extension;
        final encodedValue = event.rawExtensionData['enabled'].toString();
        await _updateServiceExtensionForStateChange(name, encodedValue);
        break;
      case DeveloperServiceEvent.socketProfilingStateChange:
        final name = extensions.socketProfiling.extension;
        final encodedValue = event.rawExtensionData['enabled'].toString();
        await _updateServiceExtensionForStateChange(name, encodedValue);
    }
  }

  Future<void> _handleDebugEvent(Event event) async {
    if (event.kind == EventKind.kResume) {
      final isolateRef = event.isolate!;
      final callbacks = _callbacksOnIsolateResume[isolateRef] ?? [];
      _callbacksOnIsolateResume = {};
      for (final callback in callbacks) {
        try {
          await callback();
        } catch (e, st) {
          _log.shout('Error running isolate callback: $e', e, st);
        }
      }
    }
  }

  Future<void> _updateServiceExtensionForStateChange(
    String name,
    String encodedValue,
  ) async {
    final ext = extensions.serviceExtensionsAllowlist[name];
    if (ext != null) {
      final extensionValue = _getExtensionValue(name, encodedValue);
      final enabled = ext is extensions.ToggleableServiceExtension
          ? extensionValue == ext.enabledValue
          // For extensions that have more than two states
          // (enabled / disabled), we will always consider them to be
          // enabled with the current value.
          : true;

      await setServiceExtensionState(
        name,
        enabled: enabled,
        value: extensionValue,
        callExtension: false,
      );
    }
  }

  Object _getExtensionValue(String name, String encodedValue) {
    final firstValue =
        extensions.serviceExtensionsAllowlist[name]!.values.first;
    return switch (firstValue) {
      bool() => encodedValue == 'true',
      num() => num.parse(encodedValue),
      _ => encodedValue,
    };
  }

  Future<void> _onFrameEventReceived() async {
    if (_firstFrameEventReceived) {
      // The first frame event was already received.
      return;
    }
    _firstFrameReceived.complete();

    final extensionsToProcess = _pendingServiceExtensions.toList();
    _pendingServiceExtensions.clear();
    await [
      for (final extension in extensionsToProcess)
        _addServiceExtension(extension)
    ].wait;
  }

  Future<void> _onMainIsolateChanged() async {
    if (_isolateManager.mainIsolate.value == null) {
      _mainIsolateClosed();
      return;
    }
    _checkForFirstFrameStarted = false;

    final isolateRef = _isolateManager.mainIsolate.value!;
    final isolate = await _isolateManager.isolateState(isolateRef).isolate;

    if (isolate == null) return;

    await _registerMainIsolate(isolate, isolateRef);
  }

  Future<void> _registerMainIsolate(
    Isolate mainIsolate,
    IsolateRef? expectedMainIsolateRef,
  ) async {
    if (expectedMainIsolateRef != _isolateManager.mainIsolate.value) {
      // Isolate has changed again.
      return;
    }

    if (mainIsolate.extensionRPCs case final extensionRpcs?) {
      if (await connectedApp.isFlutterApp) {
        if (expectedMainIsolateRef != _isolateManager.mainIsolate.value) {
          // Isolate has changed again.
          return;
        }
        await [
          for (final extension in extensionRpcs)
            _maybeAddServiceExtension(extension)
        ].wait;
      } else {
        await [
          for (final extension in extensionRpcs) _addServiceExtension(extension)
        ].wait;
      }
    }
  }

  Future<void> _maybeCheckForFirstFlutterFrame() async {
    final lastMainIsolate = _isolateManager.mainIsolate.value;
    if (_checkForFirstFrameStarted ||
        _firstFrameEventReceived ||
        lastMainIsolate == null) {
      return;
    }
    if (!isServiceExtensionAvailable(extensions.didSendFirstFrameEvent)) {
      return;
    }
    _checkForFirstFrameStarted = true;

    try {
      final value = await _service!.callServiceExtension(
        extensions.didSendFirstFrameEvent,
        isolateId: lastMainIsolate.id,
      );
      if (lastMainIsolate != _isolateManager.mainIsolate.value) {
        // The active isolate has changed since we started querying the first
        // frame.
        return;
      }
      final didSendFirstFrameEvent = value.json!['enabled'] == 'true';

      if (didSendFirstFrameEvent) {
        await _onFrameEventReceived();
      }
    } on RPCError catch (e) {
      if (e.code == RPCErrorKind.kServerError.code) {
        // Connection disappeared
        return;
      }
      rethrow;
    }
  }

  Future<void> _maybeAddServiceExtension(String? name) async {
    if (name == null) return;
    if (_firstFrameEventReceived ||
        !extensions.isUnsafeBeforeFirstFlutterFrame(name)) {
      await _addServiceExtension(name);
    } else {
      _pendingServiceExtensions.add(name);
    }
  }

  Future<void> _addServiceExtension(String name) async {
    if (_serviceExtensions.contains(name)) {
      // If the service extension was already added we do not need to add it
      // again. This can happen depending on the timing between when extension
      // added events were received and when we requested the list of all
      // service extensions already defined for the isolate.
      return;
    }
    _hasServiceExtension(name).value = true;

    final enabledServiceExtension = _enabledServiceExtensions[name];
    if (enabledServiceExtension != null) {
      // Restore any previously enabled states by calling their service
      // extension. This will restore extension states on the device after a hot
      // restart. [_enabledServiceExtensions] will be empty on page refresh or
      // initial start.
      try {
        final called = await _callServiceExtensionIfReady(
          name,
          enabledServiceExtension.value,
        );
        if (called) {
          // Only mark `name` as an "added service extension" if it was truly
          // added. If it was added, then subsequent calls to
          // `_addServiceExtension` with `name` will return early. If it was not
          // really added, then subsequent calls to `_addServiceExtension` with
          // `name` will proceed as usual.
          _serviceExtensions.add(name);
        }
        return;
      } on SentinelException catch (_) {
        // Service extension stopped existing while calling, so do nothing.
        // This typically happens during hot restarts.
      }
    } else {
      // Set any extensions that are already enabled on the device. This will
      // enable extension states in DevTools on page refresh or initial start.
      final restored = await _restoreExtensionFromDeviceIfReady(name);
      if (restored) {
        // Only mark `name` as an "added service extension" if it was truly
        // restored. If it was restored, then subsequent calls to
        // `_addServiceExtension` with `name` will return early. If it was not
        // really restored, then subsequent calls to `_addServiceExtension`
        // with `name` will proceed as usual.
        _serviceExtensions.add(name);
      }
    }
  }

  IsolateRef? get _mainIsolate => _isolateManager.mainIsolate.value;

  /// Restores the service extension named [name] from the device.
  ///
  /// Returns whether isolates in the connected app are prepared for the restore.
  Future<bool> _restoreExtensionFromDeviceIfReady(String name) async {
    final isolateRef = _isolateManager.mainIsolate.value;
    if (isolateRef == null) return false;

    final serviceExtension = extensions.serviceExtensionsAllowlist[name];
    if (serviceExtension == null) {
      return true;
    }
    final firstValue = serviceExtension.values.first;

    if (isolateRef != _mainIsolate) return false;

    final isolate = await _isolateManager.isolateState(isolateRef).isolate;
    if (isolateRef != _mainIsolate) return false;

    /// Restores the service extension named [name].
    ///
    /// Returns whether isolates in the connected app are prepared for the
    /// restore.
    Future<bool> restore() async {
      // The restore request is obsolete if the isolate has changed.
      if (isolateRef != _mainIsolate) return false;
      try {
        final response = await _service!.callServiceExtension(
          name,
          isolateId: isolateRef.id,
        );

        if (isolateRef != _mainIsolate) return false;

        switch (firstValue) {
          case bool():
            final enabled = response.json!['enabled'] == 'true';
            await _maybeRestoreExtension(name, enabled);
          case String():
            final String? value = response.json!['value'];
            await _maybeRestoreExtension(name, value);
          case num():
            final value = num.parse(
              response.json![name.substring(name.lastIndexOf('.') + 1)],
            );
            await _maybeRestoreExtension(name, value);
        }
      } on RPCError catch (e) {
        if (e.isServiceDisposedError) {
          return false;
        }
      } catch (e) {
        // Do not report an error if the VMService has gone away or the
        // selectedIsolate has been closed probably due to a hot restart.
        // There is no need
        // TODO(jacobr): validate that the exception is one of a short list
        // of allowed network related exceptions rather than ignoring all
        // exceptions.
      }
      return true;
    }

    // Do not try to restore Dart IO extensions for a paused isolate.
    if (extensions.isDartIoExtension(name) &&
        isolate?.pauseEvent?.kind?.contains('Pause') == true) {
      _callbacksOnIsolateResume.putIfAbsent(isolateRef, () => []).add(restore);
      return true;
    } else {
      return await restore();
    }
  }

  /// Maybe restores the service extension named [name] with [value].
  Future<void> _maybeRestoreExtension(String name, Object? value) async {
    final extensionDescription = extensions.serviceExtensionsAllowlist[name];
    if (extensionDescription is extensions.ToggleableServiceExtension) {
      if (value == extensionDescription.enabledValue) {
        await setServiceExtensionState(
          name,
          enabled: true,
          value: value,
          callExtension: false,
        );
      }
    } else {
      await setServiceExtensionState(
        name,
        enabled: true,
        value: value,
        callExtension: false,
      );
    }
  }

  /// Calls the service extension named [name] with [value].
  ///
  /// Returns whether isolates in the connected app are prepared for the call.
  Future<bool> _callServiceExtensionIfReady(String name, Object? value) async {
    if (_service == null) return false;

    final mainIsolate = _mainIsolate;
    if (mainIsolate == null) return false;

    final isolate = await _isolateManager.isolateState(mainIsolate).isolate;
    if (_mainIsolate != mainIsolate) return false;

    Future<bool> callExtension() async {
      if (_mainIsolate != mainIsolate) return false;

      assert(value != null);
      try {
        if (value is bool) {
          Future<void> call(String? isolateId, bool value) async {
            await _service!.callServiceExtension(
              name,
              isolateId: isolateId,
              args: {'enabled': value},
            );
          }

          final description = extensions.serviceExtensionsAllowlist[name];
          if (description?.shouldCallOnAllIsolates ?? false) {
            // TODO(jacobr): be more robust instead of just assuming that if the
            // service extension is available on one isolate it is available on
            // all. For example, some isolates may still be initializing so may
            // not expose the service extension yet.
            await _service!.forEachIsolate((isolate) async {
              await call(isolate.id, value);
            });
          } else {
            await call(mainIsolate.id, value);
          }
        } else if (value is String) {
          await _service!.callServiceExtension(
            name,
            isolateId: mainIsolate.id,
            args: {'value': value},
          );
        } else if (value is double) {
          await _service!.callServiceExtension(
            name,
            isolateId: mainIsolate.id,
            // The param name for a numeric service extension will be the last part
            // of the extension name (ext.flutter.extensionName => extensionName).
            args: {name.substring(name.lastIndexOf('.') + 1): value},
          );
        }
      } on RPCError catch (e) {
        if (e.code == RPCErrorKind.kServerError.code) {
          // The connection disappeared.
          return false;
        }
        rethrow;
      }

      return true;
    }

    // Do not try to call Dart IO extensions for a paused isolate.
    if (extensions.isDartIoExtension(name) &&
        isolate?.pauseEvent?.kind?.contains('Pause') == true) {
      _callbacksOnIsolateResume
          .putIfAbsent(mainIsolate, () => [])
          .add(callExtension);
      return true;
    } else {
      return await callExtension();
    }
  }

  void vmServiceClosed() {
    cancelStreamSubscriptions();
    _mainIsolateClosed();

    _enabledServiceExtensions.clear();
    _callbacksOnIsolateResume.clear();
    _connectedApp = null;
  }

  void _mainIsolateClosed() {
    _firstFrameReceived = Completer();
    _checkForFirstFrameStarted = false;
    _pendingServiceExtensions.clear();
    _serviceExtensions.clear();

    // If the isolate has closed, there is no need to wait any longer for
    // service extensions that might be registered.
    _performActionAndClearMap<Completer<bool>>(
      _maybeRegisteringServiceExtensions,
      action: (completer) => completer.safeComplete(false),
    );

    _performActionAndClearMap<ValueNotifier<bool>>(
      _serviceExtensionAvailable,
      action: (listenable) => listenable.value = false,
    );

    _performActionAndClearMap(
      _serviceExtensionStates,
      action: (state) => state.value = ServiceExtensionState(
        enabled: false,
        value: null,
      ),
    );
  }

  /// Performs [action] over the values in [map], and then clears the [map] once
  /// finished.
  void _performActionAndClearMap<T>(
    Map<Object, T> map, {
    required void Function(T) action,
  }) {
    map
      ..values.forEach(action)
      ..clear();
  }

  /// Sets the state for a service extension and makes the call to the VMService.
  Future<void> setServiceExtensionState(
    String name, {
    required bool enabled,
    required Object? value,
    bool callExtension = true,
  }) async {
    if (callExtension && _serviceExtensions.contains(name)) {
      await _callServiceExtensionIfReady(name, value);
    } else if (callExtension) {
      _log.info(
        'Attempted to call extension \'$name\', but no service with that name exists',
      );
    }

    final state = ServiceExtensionState(enabled: enabled, value: value);
    _serviceExtensionState(name).value = state;

    // Add or remove service extension from [enabledServiceExtensions].
    if (enabled) {
      _enabledServiceExtensions[name] = state;
    } else {
      _enabledServiceExtensions.remove(name);
    }
  }

  bool isServiceExtensionAvailable(String name) =>
      _serviceExtensions.contains(name) ||
      _pendingServiceExtensions.contains(name);

  Future<bool> waitForServiceExtensionAvailable(String name) {
    if (isServiceExtensionAvailable(name)) return Future.value(true);

    // Listen for when the service extension is added and use it.
    final completer = Completer<bool>();
    final listenable = hasServiceExtension(name);
    late final VoidCallback listener;
    listener = () {
      if (listenable.value || !completer.isCompleted) {
        listenable.removeListener(listener);
        completer.complete(true);
      }
    };
    hasServiceExtension(name).addListener(listener);

    _maybeRegisteringServiceExtensions[name] ??= completer;
    return completer.future;
  }

  ValueListenable<bool> hasServiceExtension(String name) {
    return _hasServiceExtension(name);
  }

  ValueNotifier<bool> _hasServiceExtension(String name) {
    return _serviceExtensionAvailable.putIfAbsent(
      name,
      () => ValueNotifier(_serviceExtensions.contains(name)),
    );
  }

  ValueListenable<ServiceExtensionState> getServiceExtensionState(String name) {
    return _serviceExtensionState(name);
  }

  ValueNotifier<ServiceExtensionState> _serviceExtensionState(String name) {
    return _serviceExtensionStates.putIfAbsent(
      name,
      () {
        final state = _enabledServiceExtensions[name];
        return ValueNotifier(
          state ?? ServiceExtensionState(enabled: false, value: null),
        );
      },
    );
  }

  void vmServiceOpened(
    VmService service,
    ConnectedApp connectedApp,
  ) async {
    _checkForFirstFrameStarted = false;
    cancelStreamSubscriptions();
    cancelListeners();
    _connectedApp = connectedApp;
    _service = service;
    // TODO(kenz): do we want to listen with event history here?
    autoDisposeStreamSubscription(
      service.onExtensionEvent.listen(_handleExtensionEvent),
    );
    addAutoDisposeListener(
      hasServiceExtension(extensions.didSendFirstFrameEvent),
      _maybeCheckForFirstFlutterFrame,
    );
    addAutoDisposeListener(_isolateManager.mainIsolate, _onMainIsolateChanged);
    autoDisposeStreamSubscription(
      service.onDebugEvent.listen(_handleDebugEvent),
    );
    autoDisposeStreamSubscription(
      service.onIsolateEvent.listen(_handleIsolateEvent),
    );
    final mainIsolateRef = _isolateManager.mainIsolate.value;
    if (mainIsolateRef != null) {
      _checkForFirstFrameStarted = false;
      final mainIsolate =
          await _isolateManager.isolateState(mainIsolateRef).isolate;
      if (mainIsolate != null) {
        await _registerMainIsolate(mainIsolate, mainIsolateRef);
      }
    }
  }
}

class ServiceExtensionState {
  ServiceExtensionState({required this.enabled, required this.value}) {
    if (value is bool) {
      assert(enabled == value);
    }
  }

  // For boolean service extensions, [enabled] should equal [value].
  final bool enabled;
  final Object? value;

  @override
  bool operator ==(Object other) {
    return other is ServiceExtensionState &&
        enabled == other.enabled &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        value,
      );

  @override
  String toString() {
    return 'ServiceExtensionState(enabled: $enabled, value: $value)';
  }
}

@visibleForTesting
base mixin TestServiceExtensionManager implements ServiceExtensionManager {}

extension on Event {
  Map<String, Object?> get rawExtensionData =>
      ((json as Map<String, Object?>)['extensionData'] as Map)
          .cast<String, Object?>();
}
