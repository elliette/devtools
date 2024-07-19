// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../../shared/diagnostics/diagnostics_node.dart';
import '../../../../shared/diagnostics_text_styles.dart';
import '../../../../shared/primitives/utils.dart';
import '../../../../shared/ui/icons.dart';
import '../../inspector_controller.dart';

final _colorIconMaker = ColorIconMaker();

class PropertiesView extends StatelessWidget {
  const PropertiesView({
    super.key,
    required this.controller,
    required this.node,
  });

  final InspectorController controller;
  final RemoteDiagnosticsNode node;

  Future<List<RemoteDiagnosticsNode>> loadProperties() async {
    final properties = <RemoteDiagnosticsNode>[];
    final api = node.objectGroupApi;
    if (api == null) return properties;
    try {
      final nodeProperties = await node.getProperties(api);
      properties.addAll(nodeProperties);

      for (final p in nodeProperties) {
        if (p.propertyType == 'RenderObject') {
          final renderProperties = await p.getProperties(api);
          properties.addAll(renderProperties);
        }
      }
      return Future.value(properties);
    } catch (err) {
      return Future.value(properties);
      // TODO: handle error.
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
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.all(denseSpacing),
          child: Table(
            border: TableBorder.all(
              color: theme.primaryColorLight,
              width: .5, // TODO: match DevTools outline
              borderRadius: defaultBorderRadius,
            ),
            children: [
              for (int i = 0; i < properties.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    borderRadius: _calculateBorderRadiusForRow(
                      rowIndex: i,
                      totalRows: properties.length,
                    ),
                    color: i % 2 == 0
                        ? theme.primaryColorDark
                        : theme.primaryColor,
                  ),
                  children: [
                    TableCell(
                      child: PropertyName(property: properties[i]),
                    ),
                    TableCell(
                      child: PropertyValue(
                        property: properties[i],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  BorderRadius _calculateBorderRadiusForRow({
    required int rowIndex,
    required int totalRows,
  }) {
    if (rowIndex == 0) {
      return const BorderRadius.only(
        topLeft: defaultRadius,
        topRight: defaultRadius,
      );
    }

    if (rowIndex == totalRows - 1) {
      const BorderRadius.only(
        bottomLeft: defaultRadius,
        bottomRight: defaultRadius,
      );
    }
    return BorderRadius.zero;
  }
}

class PropertyName extends StatelessWidget {
  const PropertyName({
    super.key,
    required this.property,
  });

  final RemoteDiagnosticsNode property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(denseRowSpacing),
      child: Text(
        property.name ?? '',
        style: DiagnosticsTextStyles.textStyleForLevel(
          property.level,
          theme.colorScheme,
        ).merge(theme.subtleTextStyle),
      ),
    );
  }
}

class PropertyValue extends StatelessWidget {
  const PropertyValue({
    super.key,
    required this.property,
  });

  final RemoteDiagnosticsNode property;

  static Widget _paddedIcon(Widget icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 1.0),
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final children = <Widget>[];

    final propertyType = property.propertyType;
    final properties = property.valuePropertiesJson;
    var description = property.description;

    if (propertyType != null && properties != null) {
      switch (propertyType) {
        case 'Color':
          {
            final alpha = JsonUtils.getIntMember(properties, 'alpha');
            final red = JsonUtils.getIntMember(properties, 'red');
            final green = JsonUtils.getIntMember(properties, 'green');
            final blue = JsonUtils.getIntMember(properties, 'blue');
            String radix(int chan) => chan.toRadixString(16).padLeft(2, '0');
            description = alpha == 255
                ? '#${radix(red)}${radix(green)}${radix(blue)}'
                : '#${radix(alpha)}${radix(red)}${radix(green)}${radix(blue)}';

            final color = Color.fromARGB(alpha, red, green, blue);
            children.add(_paddedIcon(_colorIconMaker.getCustomIcon(color)));
            break;
          }

        case 'IconData':
          {
            final codePoint = JsonUtils.getIntMember(properties, 'codePoint');
            if (codePoint > 0) {
              final icon = FlutterMaterialIcons.getIconForCodePoint(
                codePoint,
                colorScheme,
              );
              children.add(_paddedIcon(icon));
            }
            break;
          }
      }
    }

    children.add(
      Flexible(
        child: Padding(
          padding: const EdgeInsets.all(denseRowSpacing),
          child: Text(
            property.description ?? 'null',
            style: DiagnosticsTextStyles.regular(Theme.of(context).colorScheme),
          ),
        ),
      ),
    );

    return Row(children: children);
  }
}
