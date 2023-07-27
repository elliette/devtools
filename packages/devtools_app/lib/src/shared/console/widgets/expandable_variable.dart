// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart' hide Stack;

import '../../../shared/primitives/listenable.dart';
import '../../../shared/tree.dart';
import '../../primitives/trees.dart';

class ExpandableVariable<T extends TreeNode<T>> extends StatelessWidget {
  const ExpandableVariable({
    Key? key,
    required this.dataDisplayProvider,
    this.variable,
    this.isSelectable = true,
    this.onItemExpanded,
  }) : super(key: key);

  @visibleForTesting
  static const emptyExpandableVariableKey = Key('empty expandable variable');

  final T? variable;
  
  final Widget Function(T, void Function()) dataDisplayProvider;

  final Future<void> Function(T)? onItemExpanded;

  final bool isSelectable;

  @override
  Widget build(BuildContext context) {
    final variable = this.variable;
    if (variable == null) {
      return const SizedBox(key: emptyExpandableVariableKey);
    }
    // TODO(kenz): preserve expanded state of tree on switching frames and
    // on stepping.
    return TreeView<T>(
      dataRootsListenable:
          FixedValueListenable<List<T>>([variable]),
      dataDisplayProvider: dataDisplayProvider,
      onItemExpanded: onItemExpanded,
      isSelectable: isSelectable,
    );
  }
}
