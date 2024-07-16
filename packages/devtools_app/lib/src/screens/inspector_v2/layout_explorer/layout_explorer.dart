// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/material.dart';

import '../../../shared/console/eval/inspector_tree_v2.dart';
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
    with AutoDisposeMixin {
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InspectorTreeNode?>(
      valueListenable: controller.selectedNode,
      builder: (context, _, __) {
        return rootWidget(selected);
      },
    );
  }

}

class WidgetProperties extends StatelessWidget {
  const WidgetProperties({
    super.key,
    required this.controller,
    required this.node,
  });

  final InspectorController controller;
  final RemoteDiagnosticsNode node;

  Future<List<RemoteDiagnosticsNode>> loadProperties() {
    try {
      final api = node.objectGroupApi;
      if (api != null) {
        return node.getProperties(api);
      }
      return Future.value(<RemoteDiagnosticsNode>[]);
    } catch (err) {
      return Future.value(<RemoteDiagnosticsNode>[]);
      // handle error.
    }    
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RemoteDiagnosticsNode>>(
      // ignore: discarded_futures, FutureBuilder requires a future.
      future: loadProperties(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final properties = snapshot.data!;
        return ListView.builder(
          itemCount: properties.length,
          itemBuilder: (context, index) {
            return PropertyItem(property: properties[index]);
          },
        );
      },
    );
  }
}

class PropertyItem extends StatelessWidget {
  const PropertyItem({
    super.key,
    required this.property,
  });

  final RemoteDiagnosticsNode property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RichText(
      text: TextSpan(
        text: '${property.name!}: ',
        style: theme.boldTextStyle,
        children: <TextSpan>[
          TextSpan(
            text: property.description ?? 'null',
            style: theme.subtleTextStyle,
          ),
        ],
      ),
    );
  }
}
