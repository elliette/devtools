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

// Note: Copy the server logic from 
// devtools_app/integration_test/test_infra/run/run_test.dart instead
void main() {
  late Process devtoolsProcess;
  late WebDriver driver;
  final devtoolsUrlCompleter = Completer<String>();

  setUp(() async {
    final chromedriver = ChromeDriver();
    await chromedriver.start(debugLogging: true);

    // Start the DevTools server.
    // This command is equivalent to running `dt serve` from the repository root.
    // We run it from the `devtools_tool` directory to ensure the relative paths
    // in the tool resolve correctly.
    final devtoolsToolPath = path.join(
      Directory.current.path,
      '..',
      '..',
      'tool',
    );
    print('DEVTOOLS TOOL PATH $devtoolsToolPath');

    devtoolsProcess = await Process.start('dart', [
      'run',
      'bin/dt.dart',
      'serve',
    ], workingDirectory: devtoolsToolPath);

    // Wait for the server to be ready by listening to its output.
    devtoolsProcess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          print(line);
          const _devToolsServerAddressLine = 'Serving DevTools at ';
          if (line.contains(_devToolsServerAddressLine)) {
            // This will pull the server address from a String like:
            // "Serving DevTools at http://127.0.0.1:9104.".
            final regexp = RegExp(
              r'http:\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+',
            );
            final match = regexp.firstMatch(line);
            print('!!!!!!!!! A MATCH');
            if (match != null && !devtoolsUrlCompleter.isCompleted) {
              print('URL IS ${match.group(0)}');
              devtoolsUrlCompleter.complete(match.group(0));
              // addressCompleter.complete();
            }
          }
        });

    final devtoolsUrl = await devtoolsUrlCompleter.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw 'DevTools server did not start within 2 minutes.',
    );

    // Create a WebDriver instance.
    // This requires a running chromedriver instance.
    // You can start one with `chromedriver --port=4444`.
    driver = await createDriver(
      uri: Uri.parse('http://localhost:4444'),
      desired: Capabilities.chrome,
    );

    // Navigate to the DevTools URL.
    await driver.get(devtoolsUrl);
  });

  tearDown(() async {
    await driver.quit();
    devtoolsProcess.kill();
  });

  group('compilation', () {
    test('loads the app and has the correct title', () async {
      // Verify that the app has loaded by checking the title.
      final title = await driver.title;
      expect(title, contains('DevTools'));
    });
  });
}
