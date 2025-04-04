// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app.dart';
import 'src/framework/framework_core.dart';
import 'src/screens/debugger/syntax_highlighter.dart';
import 'src/shared/analytics/analytics_controller.dart';
import 'src/shared/config_specific/logger/logger_helpers.dart';
import 'src/shared/feature_flags.dart';
import 'src/shared/framework/app_error_handling.dart';
import 'src/shared/globals.dart';
import 'src/shared/primitives/url_utils.dart';
import 'src/shared/primitives/utils.dart';

/// Handles necessary initialization then runs DevTools.
///
/// Any initialization that needs to happen before running DevTools, regardless
/// of context, should happen here.
///
/// If any initialization is specific to running Devtools in google3 or
/// externally, then it should be added to that respective main.dart file.
/// Alternatively, the [onDevToolsInitialized] callback can be used to perform
/// additional logic that runs after DevTools initialization but before running
/// the app.
void runDevTools({
  bool integrationTestMode = false,
  bool shouldEnableExperiments = false,
  List<DevToolsJsonFile> sampleData = const [],
  List<DevToolsScreen>? screens,
  Future<void> Function()? onDevToolsInitialized,
}) {
  setupErrorHandling(() async {
    await initializeDevTools(
      integrationTestMode: integrationTestMode,
      shouldEnableExperiments: shouldEnableExperiments,
    );

    // Load the Dart syntax highlighting grammar.
    await SyntaxHighlighter.initialize();

    await onDevToolsInitialized?.call();

    // Run the app.
    runApp(
      DevToolsApp(
        screens ?? defaultScreens(sampleData: sampleData),
        await analyticsController,
      ),
    );
  });
}

@visibleForTesting
Future<void> initializeDevTools({
  bool integrationTestMode = false,
  bool shouldEnableExperiments = false,
}) async {
  initDevToolsLogging();

  // Before switching to URL path strategy, check if this URL is in the legacy
  // fragment format and redirect if necessary.
  if (_handleLegacyUrl()) return;

  usePathUrlStrategy();

  _maybeInitForIntegrationTestMode(
    integrationTestMode: integrationTestMode,
    enableExperiments: shouldEnableExperiments,
  );

  await FrameworkCore.init();
}

/// Initializes some DevTools global fields for our Flutter integration tests.
///
/// Since we call [runDevTools] from Dart code, we cannot set environment
/// variables before calling [runDevTools], and therefore have to pass in these
/// values manually to [runDevTools].
void _maybeInitForIntegrationTestMode({
  required bool integrationTestMode,
  required bool enableExperiments,
}) {
  if (!integrationTestMode) return;

  setIntegrationTestMode();
  if (enableExperiments) {
    setEnableExperiments();
  }
}

/// Checks if the request is for a legacy URL and if so, redirects to the new
/// equivalent.
///
/// Returns `true` if a redirect was performed, in which case normal app
/// initialization should be skipped.
bool _handleLegacyUrl() {
  final url = getWebUrl();
  if (url == null) return false;

  final newUrl = mapLegacyUrl(url);
  if (newUrl != null) {
    webRedirect(newUrl);
    return true;
  }

  return false;
}
