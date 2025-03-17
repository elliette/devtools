// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../shared/managers/banner_messages.dart' as banner_messages;
import '../../standalone_screen.dart';
import 'utils/utils.dart';

class DisconnectedStateBannerMessage extends banner_messages.BannerWarning {
  DisconnectedStateBannerMessage()
    : super(
        screenId: StandaloneScreenType.editorSidebar.id,
        key: _messageKey,
        buildTextSpans: (context) {
          return [
            const TextSpan(
              text:
                  'The Flutter Property Editor appears to be disconnected. Please reload.',
            ),
          ];
        },
        buildActions: (_) => [const _ReloadButton()],
      );

  static const _messageKey = Key('PropertyEditorDisconnectedBannerMessage');
}

class _ReloadButton extends StatelessWidget {
  const _ReloadButton();

  @override
  Widget build(BuildContext context) {
    return DevToolsButton(
      label: 'Reload',
      onPressed: _onPressed,
      color: Theme.of(context).colorScheme.onTertiaryContainer,
    );
  }

  void _onPressed() {
    forceReload();
  }
}
