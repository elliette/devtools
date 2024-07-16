// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/diagnostics/diagnostics_node.dart';
import '../inspector_controller.dart';
import '../layout_explorer/box/box.dart';
import '../layout_explorer/flex/flex.dart';

/// Tab that acts as a proxy to decide which widget to be displayed
class LayoutExplorerTab extends StatefulWidget {
  const LayoutExplorerTab({super.key, required this.controller});

  final InspectorController controller;

  @override
  State<LayoutExplorerTab> createState() => _LayoutExplorerTabState();
}

class _LayoutExplorerTabState extends State<LayoutExplorerTab>
    with AutomaticKeepAliveClientMixin<LayoutExplorerTab>, AutoDisposeMixin {
  InspectorController get controller => widget.controller;

  RemoteDiagnosticsNode? get selected =>
      controller.selectedNode.value?.diagnostic;

  RemoteDiagnosticsNode? previousSelection;

  Widget rootWidget(RemoteDiagnosticsNode? node) {
    Widget? layoutExplorer;
    if (node != null && FlexLayoutExplorerWidget.shouldDisplay(node)) {
      layoutExplorer = FlexLayoutExplorerWidget(controller);
    }
    if (node != null && BoxLayoutExplorerWidget.shouldDisplay(node)) {
      layoutExplorer = BoxLayoutExplorerWidget(controller);
    }

    if (layoutExplorer != null) {
      return Flex(
        direction: Axis.horizontal,
        children: [
          Expanded(
            flex: 3,
            child: layoutExplorer,
          ),
          Expanded(
            flex: 2,
            child: WidgetProperties(
              controller: controller,
              node: node!,
            ),
          ),
        ],
      );
    }

    return Center(
      child: Text(
        node != null
            ? 'Currently, Layout Explorer only supports Box and Flex-based widgets.'
            : 'Select a widget to view its layout.',
        textAlign: TextAlign.center,
        overflow: TextOverflow.clip,
      ),
    );
  }

  void onSelectionChanged() {
    if (rootWidget(previousSelection).runtimeType !=
        rootWidget(selected).runtimeType) {
      setState(() => previousSelection = selected);
    }
  }

  @override
  void initState() {
    super.initState();
    addAutoDisposeListener(controller.selectedNode, onSelectionChanged);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return rootWidget(selected);
  }

  @override
  bool get wantKeepAlive => true;
}

class WidgetProperties extends StatefulWidget {
  const WidgetProperties({
    super.key,
    required this.controller,
    required this.node,
  });

  final InspectorController controller;
  final RemoteDiagnosticsNode node;

  @override
  State<WidgetProperties> createState() => _WidgetPropertiesState();
}

class _WidgetPropertiesState extends State<WidgetProperties> {
  List<RemoteDiagnosticsNode>? widgetProperties;

  Future<void> loadProperties() async {
    try {
      final api = widget.node.objectGroupApi;
      if (api != null) {
        final properties = await widget.node.getProperties(api);
        setState(() {
          widgetProperties = properties;
        });
      }
    } catch (err) {
      print(err);
      // handle error.
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadProperties());
  }

  @override
  Widget build(BuildContext context) {
    print('widget properties are $widgetProperties');

    return const Center(
      child: Text(
        'Widget properties!',
        textAlign: TextAlign.center,
        overflow: TextOverflow.clip,
      ),
    );
  }
}
