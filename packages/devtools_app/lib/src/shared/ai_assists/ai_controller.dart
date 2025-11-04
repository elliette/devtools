// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/utils.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _log = Logger('ai_controller');

const _dartMCPStreamName = 'dart-mcp-server';
const _samplingRequestName = 'samplingRequest';

class AiController extends DisposableController
    with AutoDisposeControllerMixin {
  AiController();

  set dtd(DartToolingDaemon dtd) {
    _dtd = dtd;
  }

  DartToolingDaemon? _dtd;

  ValueListenable<bool> get canSendSamplingRequests => _canSendSamplingRequests;
  final _canSendSamplingRequests = ValueNotifier<bool>(false);

  Future<void> listenForSamplingSupport() async {
    final dtd = _dtd;
    if (dtd == null) {
      return;
    }

    await dtd.streamListen(CoreDtdServiceConstants.servicesStreamId).catchError(
      (e) {
        _log.warning('[ERROR] ${CoreDtdServiceConstants.servicesStreamId}: $e');
      },
    );

    dtd.onEvent(CoreDtdServiceConstants.servicesStreamId).listen((event) {
      if (event.kind == 'ServiceRegistered' &&
          event.data['service'] == _dartMCPStreamName &&
          event.data['method'] == _samplingRequestName) {
        _canSendSamplingRequests.value = true;
      }
    });
  }

  Future<String?> sendSamplingRequest({
    required List<String> messages,
    required int maxTokens,
  }) async {
    final dtd = _dtd;
    if (dtd == null) {
      return null;
    }
    try {
      final response = await dtd.call(
        _dartMCPStreamName,
        _samplingRequestName,
        params: {'messages': messages, 'maxTokens': maxTokens},
      );
      return response.result['value'] as String?;
    } catch (e) {
      return e.toString();
    }
  }
}
