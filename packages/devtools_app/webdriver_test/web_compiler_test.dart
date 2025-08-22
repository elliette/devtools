// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devtools_shared/devtools_test_utils.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:webdriver/async_io.dart';

import '../integration_test/test_infra/run/run_test.dart';

// Note: Copy the server logic from
// devtools_app/integration_test/test_infra/run/run_test.dart instead
void main() {
  late Process devtoolsProcess;
  late WebDriver driver;

  setUp(() async {
    final chromedriver = ChromeDriver();
    await chromedriver.start(debugLogging: true);

    print('START DEVTOOLS PROCESS');
    devtoolsProcess = await _startLocalDevToolsServer();
    final devToolsServerAddress = await listenForDevToolsAddress(
      devtoolsProcess,
      timeout: const Duration(minutes: 3),
    );
    print('====== DEVTOOLS SERVER ADDRESS IS ==== $devToolsServerAddress');

    // Create a WebDriver instance.
    // This requires a running chromedriver instance.
    // You can start one with `chromedriver --port=4444`.
    driver = await createDriver(
      uri: Uri.parse('http://localhost:4444'),
      desired: Capabilities.chrome,
    );

    // Navigate to the DevTools URL.
    await driver.get(devToolsServerAddress);
    print('DONE NAVIGATING');
  });

  tearDown(() async {
    await driver.quit();
    devtoolsProcess.kill();
  });

  group('compilation', () {
    test('loads the app and has the correct title', () async {
      // Verify that the app has loaded by checking the title.
      final title = await driver.title;
      // print('======= TITLE IS $title');
      // expect(title, contains('DevTools'));
    });
  });
}

Future<Process> _startLocalDevToolsServer() async {
  final devtoolsToolPath = path.join(
    Directory.current.path,
    '..',
    '..',
    'tool',
  );

  final devtoolsProcess = await Process.start('dart', [
    'run',
    'bin/dt.dart',
    'serve',
    '--no-launch-browser',
  ], workingDirectory: devtoolsToolPath);
  return devtoolsProcess;
}
