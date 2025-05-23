// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_shared/devtools_test_utils.dart';

import 'test_infra/run/_in_file_args.dart';
import 'test_infra/run/_test_app_driver.dart';
import 'test_infra/run/_utils.dart';
import 'test_infra/run/run_test.dart';

// To run integration tests, run the following from `devtools_app/`:
// `dart run integration_test/run_tests.dart`
//
// To see a list of arguments that you can pass to this test script, please run
// the above command with the '-h' flag.

const _testDirectory = 'integration_test/test';
const _offlineIndicator = 'integration_test/test/offline';

/// The key in [_disabledTestsForDevice] that will hold a set of tests that should
/// be skipped for all test devices.
const _testDeviceAll = 'all';

/// The set of tests that are temporarily disabled for each type of test device.
///
/// This list should be empty most of the time, but may contain a broken test
/// while a fix being worked on.
///
/// Format: `'my_example_test.dart'`.
final _disabledTestsForDevice = <String, Set<String>>{
  _testDeviceAll: {
    // https://github.com/flutter/devtools/issues/6592
    'eval_and_browse_test.dart',
    // https://github.com/flutter/devtools/issues/7425
    'export_snapshot_test.dart',
  },
  TestAppDevice.flutterChrome.name: {
    // TODO(https://github.com/flutter/devtools/issues/7145): Figure out why
    // this fails on bots but passes locally and enable.
    'eval_and_inspect_test.dart',
    // TODO(https://github.com/flutter/devtools/issues/7732): fix and unskip.
    'debugger_panel_test.dart',
  },
};

void main(List<String> args) async {
  final testRunnerArgs = DevToolsAppTestRunnerArgs(
    args,
    verifyValidTarget: false,
  );

  await runOneOrManyTests<DevToolsAppTestRunnerArgs>(
    testDirectoryPath: _testDirectory,
    testRunnerArgs: testRunnerArgs,
    runTest: _runTest,
    newArgsGenerator: (args) => DevToolsAppTestRunnerArgs(args),
    testIsSupported: (testFile) =>
        testRunnerArgs.testAppDevice.supportsTest(testFile.path),
    debugLogging: debugTestScript,
  );
}

Future<void> _runTest(DevToolsAppTestRunnerArgs testRunnerArgs) async {
  final testTarget = testRunnerArgs.testTarget!;
  final testDevice = testRunnerArgs.testAppDevice.name;

  final disabledForAllDevices = _disabledTestsForDevice[_testDeviceAll]!;
  final disabledForDevice = _disabledTestsForDevice[testDevice] ?? {};
  final disabled = {
    ...disabledForAllDevices,
    ...disabledForDevice,
  }.any((t) => testTarget.endsWith(t));
  if (disabled) {
    debugLog('Disabled test - skipping $testTarget for $testDevice.');
    return;
  }

  if (!testRunnerArgs.testAppDevice.supportsTest(testTarget)) {
    debugLog('Unsupported test - skipping $testTarget for $testDevice.');
    return;
  }

  await runFlutterIntegrationTest(
    testRunnerArgs,
    TestFileArgs(testTarget, testAppDevice: testRunnerArgs.testAppDevice),
    offline: testTarget.startsWith(_offlineIndicator),
  );
}
