// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:dds_service_extensions/dap.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart' hide Error;

import '../shared/globals.dart';
import '../shared/primitives/auto_dispose.dart';
import '../shared/primitives/message_bus.dart';
import '../shared/primitives/utils.dart';
import '../shared/utils.dart';
import 'isolate_state.dart';
import 'service_extensions.dart' as extensions;
import 'vm_service_wrapper.dart';

class IsolateCache {
  // IsolateCache();

  final _isolateRefToState = <IsolateRef, IsolateState>{};
  final _isolateNumberToState = <int, IsolateState>{};

  bool get isEmpty =>
      _isolateRefToState.isEmpty && _isolateNumberToState.isEmpty;

  IsolateRef? get firstRef => _isolateRefToState.keys.first;

  List<IsolateState> get states => _isolateRefToState.values.toList();

  List<IsolateRef> get refs => _isolateRefToState.keys.toList();

  List<int> get numbers => _isolateNumberToState.keys.toList();

  bool containsRef(IsolateRef isolateRef) {
    return _isolateRefToState.containsKey(isolateRef);
  }

  bool containsNumber(int isolateNumber) {
    return _isolateNumberToState.containsKey(isolateNumber);
  }

  IsolateState? getStateForRef(IsolateRef isolateRef) {
    return _isolateRefToState[isolateRef];
  }

  IsolateState? getStateForNumber(int isolateNumber) {
    return _isolateNumberToState[isolateNumber];
  }

  IsolateState addIsolate(IsolateRef isolateRef, IsolateState isolateState) {
    final state = _isolateRefToState.putIfAbsent(
      isolateRef,
      () => isolateState,
    );
    _isolateRefToState[isolateRef] = isolateState;
    final isolateNumber = isolateRef.number;
    if (isolateNumber != null) {
      _isolateNumberToState.putIfAbsent(
        int.parse(isolateNumber),
        () => isolateState,
      );
    }
    return state;
  }

  IsolateState? removeIsolate(IsolateRef isolateRef) {
    final removed = _isolateRefToState.remove(isolateRef);
    final isolateNumber = isolateRef.number;
    if (isolateNumber != null) {
      _isolateNumberToState.remove(int.parse(isolateNumber));
    }
    return removed;
  }

  void clear() {
    _isolateRefToState.clear();
    _isolateNumberToState.clear();
  }
}

class IsolateManager extends Disposer {
  final _isolateCache = IsolateCache();
  VmServiceWrapper? _service;

  final StreamController<IsolateRef?> _isolateCreatedController =
      StreamController<IsolateRef?>.broadcast();
  final StreamController<IsolateRef?> _isolateExitedController =
      StreamController<IsolateRef?>.broadcast();

  ValueListenable<IsolateRef?> get selectedIsolate => _selectedIsolate;
  final _selectedIsolate = ValueNotifier<IsolateRef?>(null);

  int _lastIsolateIndex = 0;
  final Map<String?, int> _isolateIndexMap = {};

  ValueListenable<List<IsolateRef>> get isolates => _isolates;
  final _isolates = ListValueNotifier(const <IsolateRef>[]);

  Stream<IsolateRef?> get onIsolateCreated => _isolateCreatedController.stream;

  Stream<IsolateRef?> get onIsolateExited => _isolateExitedController.stream;

  ValueListenable<IsolateRef?> get mainIsolate => _mainIsolate;
  final _mainIsolate = ValueNotifier<IsolateRef?>(null);

  final _isolateRunnableCompleters = <String?, Completer<void>>{};

  Future<void> init(List<IsolateRef> isolates) async {
    // Re-initialize isolates when VM developer mode is enabled/disabled to
    // display/hide system isolates.
    addAutoDisposeListener(preferences.vmDeveloperModeEnabled, () async {
      final vm = await serviceManager.service!.getVM();
      final isolates = vm.isolatesForDevToolsMode();
      final vmDeveloperModeEnabled = preferences.vmDeveloperModeEnabled.value;
      if (selectedIsolate.value!.isSystemIsolate! && !vmDeveloperModeEnabled) {
        selectIsolate(_isolates.value.first);
      }
      await _initIsolates(isolates);
    });
    await _initIsolates(isolates);
  }

  IsolateState? get mainIsolateState {
    return _mainIsolate.value != null
        ? _isolateCache.getStateForRef(_mainIsolate.value!)
        : null;
  }

  /// Return a unique, monotonically increasing number for this Isolate.
  int? isolateIndex(IsolateRef isolateRef) {
    if (!_isolateIndexMap.containsKey(isolateRef.id)) {
      _isolateIndexMap[isolateRef.id] = ++_lastIsolateIndex;
    }
    return _isolateIndexMap[isolateRef.id];
  }

  void selectIsolate(IsolateRef? isolateRef) {
    _setSelectedIsolate(isolateRef);
  }

  Future<void> _initIsolates(List<IsolateRef> isolates) async {
    _clearIsolateStates();

    await Future.wait([
      for (final isolateRef in isolates) _registerIsolate(isolateRef),
    ]);

    // It is critical that the _serviceExtensionManager is already listening
    // for events indicating that new extension rpcs are registered before this
    // call otherwise there is a race condition where service extensions are not
    // described in the selectedIsolate or received as an event. It is ok if a
    // service extension is included in both places as duplicate extensions are
    // handled gracefully.
    await _initSelectedIsolate();
  }

  Future<void> _registerIsolate(IsolateRef isolateRef) async {
    assert(!_isolateCache.containsRef(isolateRef));
    _isolateCache.addIsolate(isolateRef, IsolateState(isolateRef));
    _isolates.add(isolateRef);
    isolateIndex(isolateRef);
    await _loadIsolateState(isolateRef);
  }

  Future<void> _loadIsolateState(IsolateRef isolateRef) async {
    final service = _service;
    var isolate = await _service!.getIsolate(isolateRef.id!);
    if (isolate.runnable == false) {
      final isolateRunnableCompleter = _isolateRunnableCompleters.putIfAbsent(
        isolate.id,
        () => Completer<void>(),
      );
      if (!isolateRunnableCompleter.isCompleted) {
        await isolateRunnableCompleter.future;
        isolate = await _service!.getIsolate(isolate.id!);
      }
    }
    if (service != _service) return;
    final state = _isolateCache.getStateForRef(isolateRef);
    if (state != null) {
      // Isolate might have already been closed.
      state.handleIsolateLoad(isolate);
    }
  }

  Future<void> _handleIsolateEvent(Event event) async {
    _sendToMessageBus(event);
    if (event.kind == EventKind.kIsolateRunnable) {
      final isolateRunnable = _isolateRunnableCompleters.putIfAbsent(
        event.isolate!.id,
        () => Completer<void>(),
      );
      isolateRunnable.complete();
    } else if (event.kind == EventKind.kIsolateStart &&
        !event.isolate!.isSystemIsolate!) {
      await _registerIsolate(event.isolate!);
      _isolateCreatedController.add(event.isolate);
      // TODO(jacobr): we assume the first isolate started is the main isolate
      // but that may not always be a safe assumption.
      _mainIsolate.value ??= event.isolate;

      if (_selectedIsolate.value == null) {
        _setSelectedIsolate(event.isolate);
      }
    } else if (event.kind == EventKind.kServiceExtensionAdded) {
      // Check to see if there is a new isolate.
      if (_selectedIsolate.value == null &&
          extensions.isFlutterExtension(event.extensionRPC!)) {
        _setSelectedIsolate(event.isolate);
      }
    } else if (event.kind == EventKind.kIsolateExit) {
      final isolateRef = event.isolate;
      if (isolateRef != null) {
        _isolateCache.removeIsolate(isolateRef)?.dispose();
        _isolates.remove(isolateRef);
      }
      _isolateExitedController.add(event.isolate);
      if (_mainIsolate.value == event.isolate) {
        _mainIsolate.value = null;
      }
      if (_selectedIsolate.value == event.isolate) {
        _selectedIsolate.value =
            _isolateCache.isEmpty ? null : _isolateCache.firstRef;
      }
      _isolateRunnableCompleters.remove(event.isolate!.id);
    }
  }

  void _sendToMessageBus(Event event) {
    messageBus.addEvent(
      BusEvent(
        'debugger',
        data: event,
      ),
    );
  }

  Future<void> _initSelectedIsolate() async {
    if (_isolateCache.isEmpty) {
      return;
    }
    _mainIsolate.value = null;
    final service = _service;
    final mainIsolate = await _computeMainIsolate();
    if (service != _service) return;
    _mainIsolate.value = mainIsolate;
    _setSelectedIsolate(_mainIsolate.value);
  }

  Future<IsolateRef?> _computeMainIsolate() async {
    if (_isolateCache.isEmpty) return null;

    final service = _service;
    for (var isolateState in _isolateCache.states) {
      if (_selectedIsolate.value == null) {
        final isolate = await isolateState.isolate;
        if (service != _service) return null;
        for (String extensionName in isolate?.extensionRPCs ?? []) {
          if (extensions.isFlutterExtension(extensionName)) {
            return isolateState.isolateRef;
          }
        }
      }
    }

    final IsolateRef? ref =
        _isolateCache.refs.firstWhereOrNull((IsolateRef ref) {
      // 'foo.dart:main()'
      return ref.name!.contains(':main(');
    });

    return ref ?? _isolateCache.firstRef;
  }

  void _setSelectedIsolate(IsolateRef? ref) {
    _selectedIsolate.value = ref;
  }

  void handleVmServiceClosed() {
    cancelStreamSubscriptions();
    _selectedIsolate.value = null;
    _service = null;
    _lastIsolateIndex = 0;
    _setSelectedIsolate(null);
    _isolateIndexMap.clear();
    _clearIsolateStates();
    _mainIsolate.value = null;
    _isolateRunnableCompleters.clear();
  }

  void _clearIsolateStates() {
    for (var isolateState in _isolateCache.states) {
      isolateState.dispose();
    }
    _isolateCache.clear();
    _isolates.clear();
  }

  void vmServiceOpened(VmServiceWrapper service) async {
    _selectedIsolate.value = null;

    cancelStreamSubscriptions();
    _service = service;
    autoDisposeStreamSubscription(
      service.onIsolateEvent.listen(_handleIsolateEvent),
    );
    autoDisposeStreamSubscription(
      service.onDebugEvent.listen(_handleDebugEvent),
    );

    // Listen for DAP events:
    print('Sending init dap');
    await service.initDap();
    print('done sending initDap');
    autoDisposeStreamSubscription(
      service.onDAPEvent.listen(_handleDapEvent),
    );

    // We don't know the main isolate yet.
    _mainIsolate.value = null;
  }

  IsolateState isolateState(IsolateRef isolateRef) {
    return _isolateCache.addIsolate(isolateRef, IsolateState(isolateRef));
  }

  void _handleDebugEvent(Event event) {
    final isolate = event.isolate;
    if (isolate == null) return;
    final isolateState = _isolateCache.getStateForRef(isolate);
    if (isolateState == null) {
      return;
    }

    isolateState.handleDebugEvent(event.kind);
  }

  void _handleDapEvent(Event event) {
    print('handle dap event $event');
    // final data = event.dapData.toJson();
    if (event.dapData.body == null) return;
    final body = event.dapData.body as Map<String, dynamic>;
    // The DAP threadId is equaivalent to the isolate number.
    final isolateNumber = body['threadId'] as int?;
    if (isolateNumber == null) return;
    final isolateState = _isolateCache.getStateForNumber(isolateNumber);
    if (isolateState == null) {
      print(
          'no matching isolate for $isolateNumber, numbers are ${_isolateCache.numbers}');
      return;
    }
  }
}
