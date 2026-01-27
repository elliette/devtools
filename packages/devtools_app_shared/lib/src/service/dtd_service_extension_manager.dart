// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:core';

import 'package:collection/collection.dart';
import 'package:dds_service_extensions/dds_service_extensions.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart' hide Error;

import '../utils/auto_dispose.dart';
import '../utils/utils.dart';
import 'connected_app.dart';
import 'dtd_manager.dart';
import 'eval_on_dart_library.dart' hide SentinelException;
import 'flutter_version.dart';
import 'isolate_manager.dart';
import 'isolate_state.dart';
import 'resolved_uri_manager.dart';
import 'service_extension_manager.dart';
import 'service_extensions.dart';
import 'service_utils.dart';

final _log = Logger('dtd_service_extension_manager');

class DTDServiceExtensionManager {
  DTDServiceExtensionManager(ValueListenable<DartToolingDaemon?> dtd)
      : _dtdConnection = dtd {
    _init();
  }

  final ValueListenable<DartToolingDaemon?> _dtdConnection;

  Stream<DTDEvent>? _serviceEventsStream;
  Stream<DTDEvent> get serviceEventsStream => _serviceEventsStream!;

  Stream<DTDEvent>? _serviceRegistrationStream;
  Stream<DTDEvent> get serviceRegistrationStream => _serviceRegistrationStream!;

  // final _registeredServiceNotifiers = <String, ImmediateValueNotifier<bool>>{};

  /// Mapping of service name to service method.
  Map<String, Set<String>> get registeredMethodsForService =>
      _registeredMethodsForService;
  final _registeredMethodsForService = <String, Set<String>>{};

  void _init() {
    _dtdConnection.addListener(_listenToDtdServices);
  }

  Future<void> _listenToDtdServices() async {
    final dtd = _dtdConnection.value;
    if (dtd == null) {
      _serviceEventsStream = null;
      _serviceRegistrationStream = null;
      return;
    }

    await dtd.streamListen(CoreDtdServiceConstants.servicesStreamId).catchError(
      (error) {
        print('error listening to DTD stream: $error');
        //  _log.warning(error);
      },
    );

    _serviceEventsStream = dtd
        .onEvent(CoreDtdServiceConstants.servicesStreamId)
        .asBroadcastStream();

    _serviceRegistrationStream =
        _serviceEventsStream!.where(_isRegistrationEvent).asBroadcastStream();


    // dtd
    //     .onEvent(CoreDtdServiceConstants.servicesStreamId)
    //     .listen(_listenForServices);
  }

  bool _isRegistrationEvent(DTDEvent event) {
    final isServiceRegistration = event.kind == EventKind.kServiceRegistered;
    final isServiceUnregistration =
        event.kind == EventKind.kServiceUnregistered;

    return isServiceRegistration || isServiceUnregistration;
  }

  Future<void> _listenForServices(DTDEvent event) async {
    print('EVENT KIND IS ${event.kind}...');
    final isServiceRegistration = event.kind == EventKind.kServiceRegistered;
    final isServiceUnregistration =
        event.kind == EventKind.kServiceUnregistered;

    if (!isServiceRegistration && !isServiceUnregistration) return;

    final serviceName = event.data['service'] as String?;
    final serviceMethod = event.data['method'] as String?;
    print('SERVICE NAME: $serviceName, METHOD: $serviceMethod');
    if (serviceName == null || serviceMethod == null) return;

    if (isServiceRegistration) {
      _registeredMethodsForService.putIfAbsent(
          serviceName, () => _registeredMethodsForService[serviceName] ?? {});
      _registeredMethodsForService[serviceName]!.add(serviceMethod);
    } else {
      _registeredMethodsForService[serviceName]?.remove(serviceMethod);
    }

    print('-------- DTD SERVICE EXTENSION MANAGER ----------');
    printServices();
  }

  Future<void> _registeredServices() async {
    final dtd = _dtdConnection.value;
    if (dtd == null) {
      return;
    }

    final registeredServices = await dtd.getRegisteredServices();

    print('-------- DTD SERVICE EXTENSION MANAGER ----------');
    print('--- DTD Services');
    print(registeredServices.dtdServices);

    print('--- Client Services');
    if (registeredServices.clientServices.isEmpty) {
      print('No client services found.');
    } else {
      for (final service in registeredServices.clientServices) {
        final serviceName = service.name;
        final serviceMethods = service.methods;

        print('Service Name: ${service.name} - ${service.methods}');
        // Depending on the DTD version/client, you might also be able
        // to inspect available methods:
        // print('Methods: ${service.methods}');
      }
    }
  }

  void printServices() {
    for (final entry in _registeredMethodsForService.entries) {
      print('Service: ${entry.key}, Methods: ${entry.value}');
    }
  }
}
