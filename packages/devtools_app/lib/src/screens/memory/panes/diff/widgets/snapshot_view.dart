// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/memory/classes.dart';
import '../../../../../shared/primitives/utils.dart';
import '../../../../../shared/ui/common_widgets.dart';
import '../controller/diff_pane_controller.dart';
import '../data/classes_diff.dart';
import 'class_details/class_details.dart';
import 'classes_table_diff.dart';
import 'classes_table_single.dart';

class SnapshotView extends StatelessWidget {
  const SnapshotView({super.key, required this.controller});

  final DiffPaneController controller;

  @override
  Widget build(BuildContext context) {
    return MultiValueListenableBuilder(
      listenables: [
        controller.derived.singleClassesToShow,
        controller.derived.diffClassesToShow,
      ],
      builder: (_, values, _) {
        final singleClasses = values.first as ClassDataList<SingleClassData>?;
        final diffClasses = values.second as ClassDataList<DiffClassData>?;
        if (controller.derived.updatingValues) {
          return const Center(child: Text('Calculating...'));
        }

        final classes = controller.derived.classesBeforeFiltering.value;
        if (classes == null) {
          return const Center(child: Text('Processing snapshot...'));
        }

        assert((singleClasses == null) != (diffClasses == null));

        late Widget classTable;

        if (singleClasses != null) {
          classTable = ClassesTableSingle(
            classes: singleClasses,
            classesData: controller.derived.classesTableSingle,
          );
        } else if (diffClasses != null) {
          classTable = ClassesTableDiff(
            classes: controller.derived.diffClassesToShow.value!.list,
            diffData: controller.derived.classesTableDiff,
          );
        } else {
          throw StateError('singleClasses or diffClasses should not be null.');
        }

        final pathTable = ValueListenableBuilder<ClassData?>(
          valueListenable: controller.derived.classData,
          builder: (_, classData, _) => HeapClassDetails(
            classData: classData,
            pathSelection: controller.derived.selectedPath,
            isDiff: classes is ClassDataList<DiffClassData>,
            pathController: controller.retainingPathController,
          ),
        );

        return SplitPane(
          axis: Axis.vertical,
          initialFractions: const [0.4, 0.6],
          minSizes: const [80, 80],
          children: [
            OutlineDecoration.onlyBottom(child: classTable),
            OutlineDecoration.onlyTop(child: pathTable),
          ],
        );
      },
    );
  }
}
