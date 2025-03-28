// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

const verboseLoggingLevel = Level.FINEST;

/// The minimum level of logging that will be logged to the console.
///
/// BE VERY CAREFUL ABOUT CHANGING THIS VALUE IN THE REPOSITORY. IF YOU EXPOSE
/// MORE LOGS THEN THERE MAY BE PERFORMANCE IMPLICATIONS, AS A RESULT OF LOTS OF
/// LOGS ALWAYS BEING PRINTED AND SAVED.
const basicLoggingLevel = Level.INFO;

/// The icon used for Hot Reload.
const hotReloadIcon = Icons.electric_bolt_outlined;

/// The icon used for Hot Restart.
const hotRestartIcon = Icons.settings_backup_restore_outlined;

/// Number of ms per frame alloted to maintain 60fps.
const frameBudgetMs = 16;
