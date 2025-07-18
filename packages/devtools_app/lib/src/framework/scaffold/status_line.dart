// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

import '../../shared/analytics/constants.dart' as gac;
import '../../shared/framework/screen.dart';
import '../../shared/globals.dart';
import '../../shared/primitives/utils.dart';
import '../../shared/ui/common_widgets.dart';
import '../../shared/ui/utils.dart';
import '../../shared/utils/utils.dart';
import 'scaffold.dart';

/// The status line widget displayed at the bottom of DevTools.
///
/// This displays information global to the application, as well as gives pages
/// a mechanism to display page-specific information.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.currentScreen,
    required this.isEmbedded,
    required this.isConnected,
  }) : highlightForConnection = isConnected && !isEmbedded;

  final Screen currentScreen;

  final bool isEmbedded;

  final bool isConnected;

  /// Whether to highlight the footer when DevTools is connected to an app.
  final bool highlightForConnection;

  static const deviceInfoTooltip = 'Device Info';

  /// The padding around the footer in the DevTools UI.
  EdgeInsets get padding => const EdgeInsets.symmetric(
    horizontal: defaultSpacing,
    vertical: densePadding,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = highlightForConnection
        ? theme.colorScheme.primary
        : null;
    final foregroundColor = highlightForConnection
        ? theme.colorScheme.onPrimary
        : null;
    final height = statusLineHeight + padding.top + padding.bottom;
    return ValueListenableBuilder<bool>(
      valueListenable: currentScreen.showIsolateSelector,
      builder: (context, showIsolateSelector, _) {
        showIsolateSelector = showIsolateSelector && isConnected;
        return DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                top: Divider.createBorderSide(context, width: 1.0),
              ),
            ),
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            height: height,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _getStatusItems(context, showIsolateSelector),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _getStatusItems(BuildContext context, bool showIsolateSelector) {
    final theme = Theme.of(context);
    final foregroundColor = highlightForConnection
        ? theme.colorScheme.onPrimary
        : null;
    final screenWidth = ScreenSize(context).width;
    // TODO(https://github.com/flutter/devtools/issues/8913): this builds the
    // wrong status items for offline mode.
    final pageStatus = currentScreen.buildStatus(context);
    final widerThanXxs = screenWidth > MediaSize.xxs;
    final screenMetaData = ScreenMetaData.lookup(currentScreen.screenId);
    final showVideoTutorial = screenMetaData?.tutorialVideoTimestamp != null;
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DocumentationLink(
            screen: currentScreen,
            screenWidth: screenWidth,
            highlightForConnection: highlightForConnection,
          ),
          if (showVideoTutorial) ...[
            BulletSpacer(color: foregroundColor),
            VideoTutorialLink(
              screenMetaData: screenMetaData!,
              screenWidth: screenWidth,
              highlightForConnection: highlightForConnection,
            ),
          ],
        ],
      ),
      BulletSpacer(color: foregroundColor),
      if (widerThanXxs && showIsolateSelector) ...[
        IsolateSelector(foregroundColor: foregroundColor),
        BulletSpacer(color: foregroundColor),
      ],
      if (screenWidth > MediaSize.xs && pageStatus != null) ...[
        pageStatus,
        BulletSpacer(color: foregroundColor),
      ],
      buildConnectionStatus(context, screenWidth),
      if (widerThanXxs && isEmbedded) ...[
        BulletSpacer(color: foregroundColor),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: DevToolsScaffold.defaultActions(color: foregroundColor),
        ),
      ],
    ];
  }

  Widget buildConnectionStatus(BuildContext context, MediaSize screenWidth) {
    final theme = Theme.of(context);
    const noConnectionMsg = 'No client connection';
    return ValueListenableBuilder<ConnectedState>(
      valueListenable: serviceConnection.serviceManager.connectedState,
      builder: (context, connectedState, child) {
        if (connectedState.connected) {
          final app = serviceConnection.serviceManager.connectedApp!;

          String description;
          if (!app.isRunningOnDartVM!) {
            description = 'web app';
          } else {
            final vm = serviceConnection.serviceManager.vm!;
            description = vm.deviceDisplay;
          }

          final color = highlightForConnection
              ? theme.colorScheme.onPrimary
              : theme.regularTextStyle.color;

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ValueListenableBuilder(
                valueListenable: serviceConnection.serviceManager.deviceBusy,
                builder: (context, bool isBusy, _) {
                  return SizedBox(
                    width: smallProgressSize,
                    height: smallProgressSize,
                    child: isBusy
                        ? SmallCircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color?>(color),
                          )
                        : const SizedBox(),
                  );
                },
              ),
              const SizedBox(width: denseSpacing),
              DevToolsTooltip(
                message: 'Connected device',
                child: Text(
                  description,
                  style: highlightForConnection
                      ? theme.regularTextStyle.copyWith(
                          color: theme.colorScheme.onPrimary,
                        )
                      : theme.regularTextStyle,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          );
        } else {
          return child!;
        }
      },
      child: screenWidth <= MediaSize.xxs
          ? const DevToolsTooltip(
              message: noConnectionMsg,
              child: Icon(Icons.warning_amber_rounded, size: actionsIconSize),
            )
          : Text(noConnectionMsg, style: theme.regularTextStyle),
    );
  }
}

/// A widget that links to DevTools documentation on docs.flutter.dev for the
/// given [screen].
class DocumentationLink extends StatelessWidget {
  const DocumentationLink({
    super.key,
    required this.screen,
    required this.screenWidth,
    required this.highlightForConnection,
  });

  final Screen screen;

  final MediaSize screenWidth;

  final bool highlightForConnection;

  @override
  Widget build(BuildContext context) {
    final color = highlightForConnection
        ? Theme.of(context).colorScheme.onPrimary
        : null;
    final docPageId = screen.docPageId ?? '';
    return LinkIconLabel(
      icon: Icons.library_books_outlined,
      link: GaLink(
        display: screenWidth <= MediaSize.xs ? 'Docs' : 'Read docs',
        url:
            screen.docsUrl ??
            'https://docs.flutter.dev/tools/devtools/$docPageId',
        gaScreenName: screen.screenId,
        gaSelectedItemDescription: gac.documentationLink,
      ),
      color: color,
    );
  }
}

/// A widget that links to the "Dive in to DevTools" YouTube video at the
/// chapter for the given [screenMetaData].
class VideoTutorialLink extends StatelessWidget {
  const VideoTutorialLink({
    super.key,
    required this.screenMetaData,
    required this.screenWidth,
    required this.highlightForConnection,
  });

  final ScreenMetaData screenMetaData;

  final MediaSize screenWidth;

  final bool highlightForConnection;

  static const _devToolsYouTubeVideoUrl = 'https://youtu.be/_EYk-E29edo';

  @override
  Widget build(BuildContext context) {
    final color = highlightForConnection
        ? Theme.of(context).colorScheme.onPrimary
        : null;
    return LinkIconLabel(
      icon: Icons.ondemand_video_rounded,
      link: GaLink(
        display: screenWidth <= MediaSize.xs ? 'Tutorial' : 'Watch tutorial',
        url:
            '$_devToolsYouTubeVideoUrl${screenMetaData.tutorialVideoTimestamp}',
        gaScreenName: screenMetaData.id,
        gaSelectedItemDescription:
            '${gac.videoTutorialLink}-${screenMetaData.id}',
      ),
      color: color,
    );
  }
}

class IsolateSelector extends StatelessWidget {
  const IsolateSelector({super.key, required this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final isolateManager = serviceConnection.serviceManager.isolateManager;
    return MultiValueListenableBuilder(
      listenables: [isolateManager.isolates, isolateManager.selectedIsolate],
      builder: (context, values, _) {
        final isolates = values.first as List<IsolateRef>;
        final selectedIsolateRef = values.second as IsolateRef?;
        return PopupMenuButton<IsolateRef?>(
          tooltip: 'Selected Isolate',
          initialValue: selectedIsolateRef,
          onSelected: isolateManager.selectIsolate,
          itemBuilder: (BuildContext context) => isolates.map((ref) {
            return PopupMenuItem<IsolateRef>(
              value: ref,
              child: _IsolateOption(
                ref,
                // This is always rendered against the background color
                // for the pop up menu, which is the `surface` color.
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }).toList(),
          child: _IsolateOption(
            isolateManager.selectedIsolate.value,
            color: foregroundColor,
          ),
        );
      },
    );
  }
}

class _IsolateOption extends StatelessWidget {
  const _IsolateOption(this.ref, {required this.color});

  final IsolateRef? ref;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ref?.isSystemIsolate ?? false
              ? Icons.settings_applications
              : Icons.call_split,
          color: color,
        ),
        const SizedBox(width: denseSpacing),
        Text(
          ref == null ? 'isolate' : _isolateName(ref!),
          style: Theme.of(context).regularTextStyle.copyWith(color: color),
        ),
      ],
    );
  }

  String _isolateName(IsolateRef ref) {
    final name = ref.name;
    return '$name #${serviceConnection.serviceManager.isolateManager.isolateIndex(ref)}';
  }
}
