// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/analytics/analytics.dart' as ga;
import '../../../../../shared/analytics/constants.dart' as gac;
import '../controller/chart_pane_controller.dart';
import '../data/primitives.dart';

class IntervalDropdown extends StatefulWidget {
  const IntervalDropdown({super.key, required this.chartController});

  final MemoryChartPaneController chartController;

  @override
  State<IntervalDropdown> createState() => _IntervalDropdownState();
}

class _IntervalDropdownState extends State<IntervalDropdown> {
  @override
  Widget build(BuildContext context) {
    final displayTypes = ChartInterval.values
        .map<DropdownMenuItem<ChartInterval>>((ChartInterval value) {
          return DropdownMenuItem<ChartInterval>(
            value: value,
            child: Text(value.displayName),
          );
        })
        .toList();

    return RoundedDropDownButton<ChartInterval>(
      isDense: true,
      value: widget.chartController.data.displayInterval,
      onChanged: (ChartInterval? newValue) {
        final value = newValue!;
        setState(() {
          ga.select(
            gac.memory,
            '${gac.MemoryEvents.chartInterval.name}-${value.displayName}',
          );
          widget.chartController.data.displayInterval = value;
          final duration = value.duration;

          widget.chartController.event.zoomDuration = duration;
          widget.chartController.vm.zoomDuration = duration;
          widget.chartController.android.zoomDuration = duration;
        });
      },
      items: displayTypes,
    );
  }
}
