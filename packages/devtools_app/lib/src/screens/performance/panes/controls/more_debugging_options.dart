// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../../service/service_extension_widgets.dart';
import '../../../../service/service_extensions.dart' as extensions;
import '../../../../shared/globals.dart';
import 'performance_controls.dart';

class MoreDebuggingOptionsButton extends StatelessWidget {
  const MoreDebuggingOptionsButton({super.key});

  static const _width = 620.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ServiceExtensionCheckboxGroupButton(
      title: 'More debugging options',
      icon: Icons.build,
      tooltip: 'Opens a list of options you can use to help debug performance',
      minScreenWidthForText: PerformanceControls.minScreenWidthForText,
      extensions: [
        extensions.disableClipLayers,
        extensions.disableOpacityLayers,
        extensions.disablePhysicalShapeLayers,
        extensions.countWidgetBuilds,
      ],
      overlayDescription: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'After toggling a rendering layer on/off, '
            'reproduce the activity in your app to see the effects. '
            'All layers are rendered by default - disabling a '
            'layer might help identify expensive operations in your app.',
            style: theme.subtleTextStyle,
          ),
          if (serviceConnection
              .serviceManager
              .connectedApp!
              .isProfileBuildNow!) ...[
            const SizedBox(height: denseSpacing),
            RichText(
              text: TextSpan(
                text:
                    "These debugging options aren't available in profile mode. "
                    'To use them, run your app in debug mode.',
                style: theme.subtleTextStyle.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
      overlayWidth: _width,
    );
  }
}
