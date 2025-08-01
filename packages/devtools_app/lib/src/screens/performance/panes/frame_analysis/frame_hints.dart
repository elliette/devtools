// Copyright 2021 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

/// @docImport '../flutter_frames/flutter_frame_model.dart';
library;

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/material.dart';

import '../../../../service/connected_app/connected_app.dart';
import '../../../../service/service_extensions.dart' as extensions;
import '../../../../shared/analytics/constants.dart' as gac;
import '../../../../shared/globals.dart';
import '../../../../shared/primitives/utils.dart';
import '../../../../shared/ui/common_widgets.dart';
import '../../performance_utils.dart';
import '../controls/enhance_tracing/enhance_tracing.dart';
import '../controls/enhance_tracing/enhance_tracing_controller.dart';
import '../controls/enhance_tracing/enhance_tracing_model.dart';
import 'frame_analysis_model.dart';

class FrameHints extends StatelessWidget {
  const FrameHints({
    super.key,
    required this.frameAnalysis,
    required this.enhanceTracingController,
    required this.displayRefreshRate,
  });

  final FrameAnalysis frameAnalysis;

  final EnhanceTracingController enhanceTracingController;

  final double displayRefreshRate;

  @override
  Widget build(BuildContext context) {
    final frame = frameAnalysis.frame;
    final showUiJankHints = frame.isUiJanky(displayRefreshRate);
    final showRasterJankHints = frame.isRasterJanky(displayRefreshRate);
    if (!(showUiJankHints || showRasterJankHints)) {
      return const Text('No suggestions for this frame - no jank detected.');
    }

    final theme = Theme.of(context);
    final saveLayerCount = frameAnalysis.saveLayerCount;
    final intrinsicOperationsCount = frameAnalysis.intrinsicOperationsCount;
    final uiHints = showUiJankHints
        ? [
            Text('UI Jank Detected', style: theme.errorTextStyle),
            const SizedBox(height: denseSpacing),
            EnhanceTracingHint(
              longestPhase: frameAnalysis.longestUiPhase,
              enhanceTracingState: frameAnalysis.frame.enhanceTracingState,
              enhanceTracingController: enhanceTracingController,
            ),
            const SizedBox(height: densePadding),
            if (intrinsicOperationsCount > 0)
              IntrinsicOperationsHint(intrinsicOperationsCount),
          ]
        : <Widget>[];
    final rasterHints = showRasterJankHints
        ? [
            Text('Raster Jank Detected', style: theme.errorTextStyle),
            const SizedBox(height: denseSpacing),
            if (saveLayerCount > 0) CanvasSaveLayerHint(saveLayerCount),
            const SizedBox(height: denseSpacing),
            if (frame.hasShaderTime)
              ShaderCompilationHint(shaderTime: frame.shaderDuration),
            const SizedBox(height: denseSpacing),
            const GeneralRasterJankHint(),
          ]
        : <Widget>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...uiHints,
        if (showUiJankHints && showRasterJankHints)
          const SizedBox(height: defaultSpacing),
        ...rasterHints,
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final Widget message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lightbulb_outline, size: defaultIconSize),
        const SizedBox(width: denseSpacing),
        Expanded(child: message),
      ],
    );
  }
}

@visibleForTesting
class EnhanceTracingHint extends StatelessWidget {
  const EnhanceTracingHint({
    super.key,
    required this.longestPhase,
    required this.enhanceTracingState,
    required this.enhanceTracingController,
  });

  /// The longest [FramePhase] for the [FlutterFrame] this hint is for.
  final FramePhase longestPhase;

  /// The [EnhanceTracingState] that was active while drawing the [FlutterFrame]
  /// that this hint is for.
  final EnhanceTracingState? enhanceTracingState;

  final EnhanceTracingController enhanceTracingController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Hint(
      message: RichText(
        maxLines: 2,
        text: TextSpan(
          text: '',
          children: [
            TextSpan(text: longestPhase.title, style: theme.fixedFontStyle),
            TextSpan(
              text: ' was the longest UI phase in this frame. ',
              style: theme.regularTextStyle,
            ),
            ..._hintForPhase(longestPhase, theme),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _hintForPhase(FramePhase phase, ThemeData theme) {
    final phaseType = phase.type;
    // TODO(kenz): when [enhanceTracingState] is not available, use heuristics
    // to detect whether tracing was enhanced for a frame (e.g. the depth or
    // quantity of child events under build / layout / paint).
    final tracingEnhanced =
        enhanceTracingState?.enhancedFor(phaseType) ?? false;
    switch (phaseType) {
      case FramePhaseType.build:
        return _enhanceTracingHint(
          settingTitle: extensions.profileWidgetBuilds.title,
          eventDescription: 'widget built',
          tracingEnhanced: tracingEnhanced,
          theme: theme,
        );
      case FramePhaseType.layout:
        return _enhanceTracingHint(
          settingTitle: extensions.profileRenderObjectLayouts.title,
          eventDescription: 'render object laid out',
          tracingEnhanced: tracingEnhanced,
          theme: theme,
        );
      case FramePhaseType.paint:
        return _enhanceTracingHint(
          settingTitle: extensions.profileRenderObjectPaints.title,
          eventDescription: 'render object painted',
          tracingEnhanced: tracingEnhanced,
          theme: theme,
        );
      default:
        return [];
    }
  }

  List<InlineSpan> _enhanceTracingHint({
    required String settingTitle,
    required String eventDescription,
    required bool tracingEnhanced,
    required ThemeData theme,
  }) {
    if (tracingEnhanced) {
      return [
        TextSpan(
          text:
              'Since "$settingTitle" was enabled while this frame was drawn, '
              'you should be able to see timeline events for each '
              '$eventDescription.',
          style: theme.regularTextStyle,
        ),
      ];
    }
    final enhanceTracingButton = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: denseSpacing),
        child: SmallEnhanceTracingButton(
          enhanceTracingController: enhanceTracingController,
        ),
      ),
    );
    return [
      TextSpan(
        text: 'Consider enabling "$settingTitle" from the ',
        style: theme.regularTextStyle,
      ),
      enhanceTracingButton,
      TextSpan(
        text: ' options above and reproducing the behavior in your app.',
        style: theme.regularTextStyle,
      ),
    ];
  }
}

@visibleForTesting
class SmallEnhanceTracingButton extends StatelessWidget {
  const SmallEnhanceTracingButton({
    super.key,
    required this.enhanceTracingController,
  });

  final EnhanceTracingController enhanceTracingController;

  @override
  Widget build(BuildContext context) {
    return GaDevToolsButton(
      label: EnhanceTracingButton.title,
      icon: EnhanceTracingButton.icon,
      gaScreen: gac.performance,
      gaSelection: gac.PerformanceEvents.enhanceTracingButtonSmall.name,
      onPressed: enhanceTracingController.showEnhancedTracingMenu,
    );
  }
}

@visibleForTesting
class IntrinsicOperationsHint extends StatelessWidget {
  const IntrinsicOperationsHint(this.intrinsicOperationsCount, {super.key});

  static const _intrinsicOperationsDocs =
      'https://flutter.dev/to/minimize-layout-passes';

  final int intrinsicOperationsCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Hint(
      message: _ExpensiveOperationHint(
        docsUrl: _intrinsicOperationsDocs,
        gaScreenName: gac.performance,
        gaSelectedItemDescription:
            gac.PerformanceDocs.intrinsicOperationsDocs.name,
        message: TextSpan(
          children: [
            TextSpan(text: 'Intrinsic', style: theme.fixedFontStyle),
            TextSpan(
              text:
                  ' passes were performed $intrinsicOperationsCount '
                  '${pluralize('time', intrinsicOperationsCount)} during this '
                  'frame.',
              style: theme.regularTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}

// TODO(kenz): if the 'profileRenderObjectPaints' service extension is disabled,
// suggest that the user turn it on to get information about the render objects
// that are calling saveLayer. If the event has render object information in the
// args, display it in the hint.
@visibleForTesting
class CanvasSaveLayerHint extends StatelessWidget {
  const CanvasSaveLayerHint(this.saveLayerCount, {super.key});

  static const _saveLayerDocs = 'https://flutter.dev/to/save-layer-perf';

  final int saveLayerCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Hint(
      message: _ExpensiveOperationHint(
        docsUrl: _saveLayerDocs,
        gaScreenName: gac.performance,
        gaSelectedItemDescription: gac.PerformanceDocs.canvasSaveLayerDocs.name,
        message: TextSpan(
          children: [
            TextSpan(text: 'Canvas.saveLayer()', style: theme.fixedFontStyle),
            TextSpan(
              text:
                  ' was called $saveLayerCount '
                  '${pluralize('time', saveLayerCount)} during this frame.',
              style: theme.regularTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
class ShaderCompilationHint extends StatelessWidget {
  const ShaderCompilationHint({super.key, required this.shaderTime});

  final Duration shaderTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Hint(
      message: _ExpensiveOperationHint(
        docsUrl: preCompileShadersDocsUrl,
        gaScreenName: gac.performance,
        gaSelectedItemDescription:
            gac.PerformanceDocs.shaderCompilationDocs.name,
        message: TextSpan(
          children: [
            TextSpan(
              text: durationText(
                shaderTime,
                unit: DurationDisplayUnit.milliseconds,
              ),
              style: theme.fixedFontStyle,
            ),
            TextSpan(
              text: ' of shader compilation occurred during this frame.',
              style: theme.regularTextStyle,
            ),
          ],
        ),
        childrenSpans: serviceConnection.serviceManager.connectedApp!.isIosApp
            ? [
                TextSpan(
                  text:
                      ' Note: pre-compiling shaders is a legacy solution with many '
                      'pitfalls. Try ',
                  style: theme.regularTextStyle,
                ),
                GaLinkTextSpan(
                  link: GaLink(
                    display: 'Impeller',
                    url: impellerDocsUrl,
                    gaScreenName: gac.performance,
                    gaSelectedItemDescription:
                        gac.PerformanceDocs.impellerDocsLink.name,
                  ),
                  context: context,
                ),
                TextSpan(text: ' instead!', style: theme.regularTextStyle),
              ]
            : [],
      ),
    );
  }
}

@visibleForTesting
class GeneralRasterJankHint extends StatelessWidget {
  const GeneralRasterJankHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Hint(
      message: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text:
                  'To learn about rendering performance in Flutter, check '
                  'out the Flutter documentation on ',
              style: theme.regularTextStyle,
            ),
            GaLinkTextSpan(
              link: GaLink(
                display: 'Performance & Optimization',
                url: flutterPerformanceDocsUrl,
                gaScreenName: gac.performance,
                gaSelectedItemDescription:
                    gac.PerformanceDocs.flutterPerformanceDocs.name,
              ),
              context: context,
            ),
            TextSpan(text: '.', style: theme.regularTextStyle),
          ],
        ),
      ),
    );
  }
}

class _ExpensiveOperationHint extends StatelessWidget {
  const _ExpensiveOperationHint({
    required this.message,
    required this.docsUrl,
    required this.gaScreenName,
    required this.gaSelectedItemDescription,
    this.childrenSpans = const <TextSpan>[],
  });

  final TextSpan message;
  final String docsUrl;
  final String gaScreenName;
  final String gaSelectedItemDescription;
  final List<TextSpan> childrenSpans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        children: [
          message,
          TextSpan(text: ' This may ', style: theme.regularTextStyle),
          GaLinkTextSpan(
            context: context,
            link: GaLink(
              display: 'negatively affect your app\'s performance',
              url: docsUrl,
              gaScreenName: gaScreenName,
              gaSelectedItemDescription:
                  'frameAnalysis_$gaSelectedItemDescription',
            ),
          ),
          TextSpan(text: '.', style: theme.regularTextStyle),
          ...childrenSpans,
        ],
      ),
    );
  }
}
