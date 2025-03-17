// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:dtd/dtd.dart';
import 'package:flutter/material.dart';

import '../shared/framework/screen.dart';
import '../shared/globals.dart';
import '../shared/managers/banner_messages.dart';
import '../shared/ui/common_widgets.dart';
import 'ide_shared/property_editor/property_editor_panel.dart';
import 'vs_code/flutter_panel.dart';

/// "Screens" that are intended for standalone use only, likely for embedding
/// directly in an IDE.
///
/// A standalone screen is one that will only be available at a specific route,
/// meaning that this screen will not be part of DevTools' normal navigation.
/// The only way to access a standalone screen is directly from the url.
enum StandaloneScreenType {
  editorSidebar,
  propertyEditor,
  vsCodeFlutterPanel; // Legacy postMessage version, shows an upgrade message.

  String get id => name;

  Widget get screen {
    return BannerMessages(screen: _screen);
  }

  Screen get _screen {
    return switch (this) {
      StandaloneScreenType.vsCodeFlutterPanel => _StandaloneScreen(
        StandaloneScreenType.vsCodeFlutterPanel.id,
        screenProvider: () => const _UnsupportedSdkMessage(),
      ),
      StandaloneScreenType.editorSidebar => _DtdConnectedScreen(
        StandaloneScreenType.editorSidebar.id,
        screenProvider: (dtd) => EditorSidebarPanel(dtd),
      ),
      StandaloneScreenType.propertyEditor => _DtdConnectedScreen(
        StandaloneScreenType.propertyEditor.id,
        screenProvider: (dtd) => PropertyEditorPanel(dtd),
      ),
    };
  }
}

/// [Screen] that returns a [CenteredCircularProgressIndicator] while it waits for
/// a [DartToolingDaemon] connection.
class _DtdConnectedScreen extends Screen {
  const _DtdConnectedScreen(super.screenId, {required this.screenProvider});

  final Widget Function(DartToolingDaemon) screenProvider;

  @override
  Widget buildScreenBody(BuildContext context) {
    return ValueListenableBuilder(
      // TODO(dantup): Add a timeout here so if dtdManager.connection
      //  doesn't complete after some period we can give some kind of
      //  useful message.
      valueListenable: dtdManager.connection,
      builder: (context, data, _) {
        final dtd = data;
        return dtd == null
            ? const CenteredCircularProgressIndicator()
            : screenProvider(dtd);
      },
    );
  }
}

class _StandaloneScreen extends Screen {
  const _StandaloneScreen(super.screenId, {required this.screenProvider});

  final Widget Function() screenProvider;

  @override
  Widget buildScreenBody(BuildContext context) {
    return screenProvider();
  }
}

class _UnsupportedSdkMessage extends StatelessWidget {
  const _UnsupportedSdkMessage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: CenteredMessage(
        message:
            'The Flutter sidebar for this SDK requires v3.96 or '
            'newer of the Dart VS Code extension',
      ),
    );
  }
}
