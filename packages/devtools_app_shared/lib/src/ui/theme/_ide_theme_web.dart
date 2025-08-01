// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:web/web.dart';

import '../../utils/url/url.dart';
import '../../utils/utils.dart';
import 'ide_theme.dart';

/// Load any IDE-supplied theming.
IdeTheme getIdeTheme() {
  final queryParams = IdeThemeQueryParams(loadQueryParams());

  final overrides = IdeTheme(
    backgroundColor: queryParams.backgroundColor,
    foregroundColor: queryParams.foregroundColor,
    embedMode: queryParams.embedMode,
    isDarkMode: queryParams.darkMode,
  );

  // If the environment has provided a background color, set it immediately
  // to avoid a white page until the first Flutter frame is rendered.
  if (overrides.backgroundColor != null) {
    document.body!.style.backgroundColor =
        toCssHexColor(overrides.backgroundColor!);
  }

  return overrides;
}
