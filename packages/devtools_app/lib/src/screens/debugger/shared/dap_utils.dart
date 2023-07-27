// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dap/dap.dart' as dap;

import 'package:vm_service/vm_service.dart' hide Stack;

import '../../../shared/globals.dart';

Future<dap.Variable?> dapVariableForInstance({
  required InstanceRef instanceRef,
  required IsolateRef isolateRef,
}) async {
  final instanceId = instanceRef.id;
  final isolateId = isolateRef.id;
  if (instanceId == null || isolateId == null) return null;

  final variablesReference =
      await serviceManager.service?.dapVariableForInstanceRequest(
    instanceId,
    isolateId,
  );
  if (variablesReference == null) return null;

  final variablesResponse = await serviceManager.service?.dapVariablesRequest(
    dap.VariablesArguments(
      variablesReference: variablesReference,
    ),
  );
  return variablesResponse?.variables.first;
}
