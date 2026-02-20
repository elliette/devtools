// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../service/vm_flags.dart' as vm_flags;
import '../../shared/framework/screen.dart';
import '../../shared/globals.dart';
import '../../shared/ui/utils.dart';
import 'isolate_statistics/isolate_statistics_view.dart';
import 'object_inspector/object_inspector_view.dart';
import 'process_memory/process_memory_view.dart';
import 'queued_microtasks/queued_microtasks_view.dart';
import 'vm_developer_tools_controller.dart';
import 'vm_statistics/vm_statistics_view.dart';

abstract class VMDeveloperView {
  const VMDeveloperView({required this.title, required this.icon});

  /// The user-facing name of the page.
  final String title;

  final IconData icon;

  /// Whether this view should display the isolate selector in the status
  /// line.
  ///
  /// Some views act on all isolates; for these views, displaying a
  /// selector doesn't make sense.
  bool get showIsolateSelector => false;

  Widget build(BuildContext context);
}

class VMDeveloperToolsScreen extends Screen {
  VMDeveloperToolsScreen() : super.fromMetaData(ScreenMetaData.vmTools);

  static final id = ScreenMetaData.vmTools.id;

  static const vmStatisticsViewKey = PublicDevToolsKey(
    'vmStatisticsViewKey',
    'VM Statistics View',
  );
  static const isolateStatisticsViewKey = PublicDevToolsKey(
    'isolateStatisticsViewKey',
    'Isolate Statistics View',
  );
  static const objectInspectorViewKey = PublicDevToolsKey(
    'objectInspectorViewKey',
    'Object Inspector View',
  );
  static const vmProcessMemoryViewKey = PublicDevToolsKey(
    'vmProcessMemoryViewKey',
    'VM Process Memory View',
  );
  static const queuedMicrotasksViewKey = PublicDevToolsKey(
    'queuedMicrotasksViewKey',
    'Queued Microtasks View',
  );
  static const vmDeveloperNavigationRailKey = PublicDevToolsKey(
    'vmDeveloperNavigationRailKey',
    'VM Developer Navigation Rail',
  );

  @override
  List<PublicDevToolsKey> get keys => [
    vmStatisticsViewKey,
    isolateStatisticsViewKey,
    objectInspectorViewKey,
    vmProcessMemoryViewKey,
    queuedMicrotasksViewKey,
    vmDeveloperNavigationRailKey,
  ];

  @override
  ValueListenable<bool> get showIsolateSelector =>
      VMDeveloperToolsController.showIsolateSelector;

  @override
  Widget buildScreenBody(BuildContext context) =>
      const VMDeveloperToolsScreenBody();
}

class VMDeveloperToolsScreenBody extends StatelessWidget {
  const VMDeveloperToolsScreenBody({super.key});

  // The value of the `--profile-microtasks` VM flag cannot be modified once
  // the VM has started running.
  static final showQueuedMicrotasks =
      serviceConnection.vmFlagManager
          .flag(vm_flags.profileMicrotasks)
          ?.value
          .valueAsString ==
      'true';

  static final views = <VMDeveloperView>[
    const VMStatisticsView(),
    const IsolateStatisticsView(),
    ObjectInspectorView(),
    const VMProcessMemoryView(),
    if (showQueuedMicrotasks) const QueuedMicrotasksView(),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = screenControllers.lookup<VMDeveloperToolsController>();
    return ValueListenableBuilder<int>(
      valueListenable: controller.selectedIndex,
      builder: (context, selectedIndex, _) {
        return Row(
          children: [
            if (views.length > 1)
              highlightableWidget(
                child: NavigationRail(
                  key: VMDeveloperToolsScreen.vmDeveloperNavigationRailKey,
                  selectedIndex: selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: controller.selectIndex,
                  destinations: [
                    for (final view in views)
                      NavigationRailDestination(
                        label: Text(view.title),
                        icon: Icon(view.icon),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: defaultSpacing),
                child: IndexedStack(
                  index: selectedIndex,
                  children: [
                    for (final view in views)
                      highlightableWidget(
                        child: KeyedSubtree(
                          key: _getKeyForView(view),
                          child: view.build(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  PublicDevToolsKey? _getKeyForView(VMDeveloperView view) {
    if (view is VMStatisticsView) {
      return VMDeveloperToolsScreen.vmStatisticsViewKey;
    }
    if (view is IsolateStatisticsView) {
      return VMDeveloperToolsScreen.isolateStatisticsViewKey;
    }
    if (view is ObjectInspectorView) {
      return VMDeveloperToolsScreen.objectInspectorViewKey;
    }
    if (view is VMProcessMemoryView) {
      return VMDeveloperToolsScreen.vmProcessMemoryViewKey;
    }
    if (view is QueuedMicrotasksView) {
      return VMDeveloperToolsScreen.queuedMicrotasksViewKey;
    }
    return null;
  }
}
