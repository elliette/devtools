// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:flutter/material.dart';

import '../../../../../shared/analytics/constants.dart' as gac;
import '../../../../../shared/ui/common_widgets.dart';
import '_perfetto_desktop.dart'
    if (dart.library.js_interop) '_perfetto_web.dart';
import 'perfetto_controller.dart';

class EmbeddedPerfetto extends StatelessWidget {
  const EmbeddedPerfetto({super.key, required this.perfettoController});

  final PerfettoController perfettoController;

  @override
  Widget build(BuildContext context) {
    return Perfetto(perfettoController: perfettoController);
  }
}

class PerfettoHelpButton extends StatelessWidget {
  const PerfettoHelpButton({super.key, required this.perfettoController});

  final PerfettoController perfettoController;

  @override
  Widget build(BuildContext context) {
    return HelpButton(
      gaScreen: gac.performance,
      gaSelection: gac.PerformanceEvents.perfettoShowHelp.name,
      outlined: false,
      onPressed: perfettoController.showHelpMenu,
    );
  }
}
