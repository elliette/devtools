// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart' hide Stack;
import 'package:vm_service/vm_service.dart';

import '../../../../devtools_app.dart';
import '../../../screens/debugger/shared/dap_utils.dart';
import '../../../shared/tree.dart';
import '../../diagnostics/dap_object_node.dart';
import '../../diagnostics/dart_object_node.dart';
import '../../diagnostics/tree_builder.dart';
import 'display_provider.dart';

class ExpandableVariable<T extends TreeNode<T>> extends StatefulWidget {
  const ExpandableVariable({
    Key? key,
    required this.instanceRef,
    required this.isolateRef,
    this.isSelectable = true,
  }) : super(key: key);

  final InstanceRef instanceRef;

  final IsolateRef isolateRef;

  final bool isSelectable;

  @override
  State<ExpandableVariable<T extends TreeNode<T>>> createState() => _ExpandableVariableState<T extends TreeNode<T>>();
}

class _ExpandableVariableState<T extends TreeNode<T>> extends State<ExpandableVariable<T>> {
  late Future<T?> _nodeFuture;
  
  
  @override
  void initState() {
    super.initState();
    if (T == DapObjectNode) {
            // ignore: discarded_futures, future gets awaited in build.
      _nodeFuture = _buildDapNode(instanceRef: widget.instanceRef,
            isolateRef: widget.isolateRef,) as Future<T?>;
    } else if (T == DartObjectNode) {
      // ignore: discarded_futures, future gets awaited in build.
      _nodeFuture = _buildVmNode(instanceRef: widget.instanceRef,
            isolateRef: widget.isolateRef,) as Future<T?>;
    } else {
      _nodeFuture = Future.value();
    }
  }
  
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(future: _nodeFuture, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const CenteredCircularProgressIndicator();
        }

        final node = snapshot.data;
        if (node == null) {
          return const Text('Error!!');
        }

        if (node is DartObjectNode) {
          final vmNode = node as DartObjectNode;
              return ExpandableNode(
      node: vmNode,
      dataDisplayProvider: (node, onTap) =>
          VmDisplayProvider(node: node, onTap: onTap),
      onItemExpanded: (variable) async {
        // Lazily build the variables tree for performance reasons.
        await Future.wait(variable.children.map(buildVariablesTree));
      },
    );

        }

                if (node is DapObjectNode) {
          final dapNode = node as DapObjectNode;
              return ExpandableNode(
      node: dapNode,
      dataDisplayProvider: (node, onTap) =>
          DapDisplayProvider(node: node, onTap: onTap),
      onItemExpanded: (variable) async  {
        await variable.fetchChildren();
      },
    );

        }

                return const Text('Error!!');
      },);


  }

  Future<DapObjectNode?> _buildDapNode({
    required InstanceRef instanceRef,
    required IsolateRef isolateRef,
  }) async {
    final vmService = serviceManager.service;
    if (vmService == null) return null;
    final dapVariable = await dapVariableForInstance(
      instanceRef: instanceRef,
      isolateRef: isolateRef,
    );
    if (dapVariable == null) return null;
    final dapNode = DapObjectNode(
      variable: dapVariable,
      service: vmService,
    );
    await dapNode.fetchChildren();
    return dapNode;
  }

    Future<DartObjectNode?> _buildVmNode({
    required InstanceRef instanceRef,
    required IsolateRef isolateRef,
  }) async {
    final vmNode = DartObjectNode.fromValue(
      value: instanceRef,
      isolateRef: isolateRef,
    );
    await buildVariablesTree(vmNode);
    return vmNode;
  }
}

class ExpandableNode<T extends TreeNode<T>> extends StatelessWidget {
  const ExpandableNode({
    Key? key,
    required this.dataDisplayProvider,
    this.node,
    this.isSelectable = true,
    this.onItemExpanded,
  }) : super(key: key);

  @visibleForTesting
  static const emptyExpandableNodeKey = Key('empty expandable node');

  final T? node;

  final Widget Function(T, void Function()) dataDisplayProvider;

  final Future<void> Function(T)? onItemExpanded;

  final bool isSelectable;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node == null) {
      return const SizedBox(key: emptyExpandableNodeKey);
    }
    // TODO(kenz): preserve expanded state of tree on switching frames and
    // on stepping.
    return TreeView<T>(
      dataRootsListenable: FixedValueListenable<List<T>>([node]),
      dataDisplayProvider: dataDisplayProvider,
      onItemExpanded: onItemExpanded,
      isSelectable: isSelectable,
    );
  }
}
