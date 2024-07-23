// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'inspector_controller.dart';
import 'widget_details/widget_details.dart';

class InspectorDetails extends StatelessWidget {
  const InspectorDetails({
    required this.controller,
    super.key,
  });

  final InspectorController controller;

  @override
  Widget build(BuildContext context) {
    return WidgetDetails(
      controller: controller,
    );
  }
}
