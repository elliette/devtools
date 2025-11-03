// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:dtd/dtd.dart';
import 'package:logging/logging.dart';

final _log = Logger('ai_controller');

const _dartMCPStreamName = 'dart-mcp-server';
const _samplingRequestName = 'samplingRequest';

class AiController extends DisposableController
    with AutoDisposeControllerMixin {
  AiController();

  ValueListenable<bool> get canSendSamplingRequests => _canSendSamplingRequests;
  final _canSendSamplingRequests = ValueNotifier<bool>(false);

  Future<void> listenForSamplingSupport(DartToolingDaemon dtd) async {
    await dtd.streamListen(CoreDtdServiceConstants.servicesStreamId).catchError(
      (e) {
        _log.warning('[ERROR] ${CoreDtdServiceConstants.servicesStreamId}: $e');
      },
    );

    dtd.onEvent(CoreDtdServiceConstants.servicesStreamId).listen((event) {
      if (event.kind == 'ServiceRegistered' &&
          event.data['service'] == _dartMCPStreamName &&
          event.data['method'] == _samplingRequestName) {
        print('Update can send sampling requests');
        _canSendSamplingRequests.value = true;
      }
    });

    // await dtd.streamListen(_dartMCPStreamName).catchError((e) {
    //   _log.warning('[ERROR] $_dartMCPStreamName: $e');
    // });


    // dtd.onEvent(dartMcpServerStreamName).listen((data) {
    //   final kind = data.kind;
    //   print('Received event of $kind');
    // });
  }
}
