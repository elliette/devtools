// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/utils.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../globals.dart';
import '../utils/utils.dart';
import 'ai_message_types.dart';

class AiController extends DisposableController
    with AutoDisposeControllerMixin {
  AiController() {
    init();
  }

  static const _mcpServerName = 'DartMcpServer';
  static const _samplingRequestMethodName = 'samplingRequest';

  DartToolingDaemon? get dtd => _dtd;

  DartToolingDaemon? _dtd;

  // client ID -> ClientData
  ValueListenable<Map<String, ConnectedClient>> get connectedClients =>
      _connectedClients;
  final _connectedClients = ValueNotifier<Map<String, ConnectedClient>>({});

  List<String> get clientNames => _connectedClients.value.values
      .map((client) => client.displayName)
      .toList();

  @override
  void init() {
    super.init();
    print('INIT AI CONTROLLER!!!!!!!!');
    final dtdConnection = dtdManager.connection;
    _dtd = dtdConnection.value;
    print('DTD IS ${_dtd}');
    print('URI IS ${dtdManager.uri}');

    print('calling print services from ai controller');
    dtdManager.serviceExtensionManager.serviceRegistrationStream.listen((DTDEvent event) {
    final serviceName = event.data['service'] as String?;
    final serviceMethod = event.data['method'] as String?;
    print('IN AI CONTROLLER, RECEIVED $serviceName - $serviceMethod');
    });

    // safeUnawaited(_registeredServices());

  //   addAutoDisposeListener(dtdConnection, () async {
  //     print('DTD CONNECTION CHANGED');
  //     _dtd = dtdConnection.value;

  //     print('DTD IS NOW $_dtd');
  //     print('URI IS ${dtdManager.uri}');
  //     if (_dtd != null) {
  //       print('LISTENING TO DTD SERVICES...');
  //       await _listenToDtdServices();
  //     }
  //   });
  }

  Future<void> _registeredServices() async {
    final dtd = _dtd;
    if (dtd == null) {
      return;
    }
    final registeredServices = await dtd.getRegisteredServices();

    print('--- DTD Services ---');
    print(registeredServices.dtdServices);

    print('--- Client Services ---');
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

  Future<void> _listenToDtdServices() async {
    final dtd = _dtd;
    if (dtd == null) {
      return;
    }

    await dtd.streamListen(CoreDtdServiceConstants.servicesStreamId).catchError(
      (error) {
        print('error listening to DTD stream: $error');
        //  _log.warning(error);
      },
    );

    autoDisposeStreamSubscription(
      dtd
          .onEvent(CoreDtdServiceConstants.servicesStreamId)
          .listen(_listenForSamplingSupport),
    );
  }

  Future<void> _listenForSamplingSupport(DTDEvent event) async {
    print('EVENT KIND IS ${event.kind}...');
    final isServiceRegistration = event.kind == EventKind.kServiceRegistered;
    final isServiceUnregistration =
        event.kind == EventKind.kServiceUnregistered;

    if (!isServiceRegistration && !isServiceUnregistration) return;

    final serviceName = event.data['service'] as String?;
    final serviceMethod = event.data['method'] as String?;
    print('SERVICE NAME: $serviceName, METHOD: $serviceMethod');
    if (serviceName == null || serviceMethod == null) return;

    if (serviceName.startsWith(_mcpServerName) &&
        serviceMethod == _samplingRequestMethodName) {
      final clientId = _clientIdFromServiceName(serviceName);
      isServiceRegistration
          ? _addConnectedClient(clientId)
          : _removeConnectedClient(clientId);
    }
  }

  void _addConnectedClient(String clientId) {
    if (_connectedClients.value.containsKey(clientId)) return;

    final clientName = _clientNameFromClientId(clientId);
    final matchingClients = _connectedClients.value.values.where(
      (client) => client.name == clientName,
    );
    final number = matchingClients.length + 1;
    _connectedClients.value[clientId] = ConnectedClient(
      name: clientName,
      number: number,
    );
  }

  void _removeConnectedClient(String clientId) {
    _connectedClients.value.remove(clientId);
  }

  Future<ChatMessage> sendMessage(ChatMessage _) async {
    await Future.delayed(const Duration(seconds: 3));
    return const ChatMessage(text: _loremIpsum, isUser: false);
  }

  // DartMcpServer_gemini_cli_1234abcd -> gemini_cli_1234abcd
  // DartMcpServer_gemini_cli_5678efgh  -> _gemini_cli_5678efgh
  // DartMcpServer_github_copilot_9123ijkl -> github_copilot_9123ijkl
  String _clientIdFromServiceName(String serviceName) {
    const prefix = 'DartMcpServer_';
    if (serviceName.startsWith(prefix)) {
      return serviceName.substring(prefix.length);
    }
    return serviceName;
  }

  // gemini_cli_1234abcd -> GEMINI CLI
  // gemini_cli_5678efgh -> GEMINI CLI
  // github_copilot_9123ijkl -> GITHUB COPILOT
  String _clientNameFromClientId(String clientId) {
    final parts = clientId.split('_');
    if (parts.length > 1) {
      parts.removeLast();
      return parts.join(' ').toUpperCase();
    }
    return clientId.toUpperCase();
  }
}

const _loremIpsum = '''
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.
''';
