// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:devtools_tool/commands/shared.dart';

import '../utils.dart';

const _fromCommitArg = 'from';
const _toCommitArg = 'to';

/// A command for performing a binary search across Flutter candidates to detect a regression.
class FlutterBisectCommand extends Command {
  FlutterBisectCommand() {
    argParser.addOption(
      _fromCommitArg,
      help:
          'The Flutter commit to start the binary search from. The script should pass at this commit.',
      valueHelp: '0e0d951d058949c1b10029f1acf7322ebfe67f43',
      mandatory: true,
    );
    argParser.addOption(
      _toCommitArg,
      help:
          'The Flutter commit to end the binary search at. The script should fail at this commit.',
      valueHelp: '0e0d951d058949c1b10029f1acf7322ebfe67f43',
      mandatory: true,
    );
  }
  @override
  String get description =>
      'A command for performing a binary search across Flutter candidates to pinpoint a regression.';

  @override
  String get name => 'flutter-bisect';

  final processManager = ProcessManager();

  @override
  FutureOr? run() async {
    // Resolve the tool script path before changing the current working directory.
    final toolScript = Platform.script.toFilePath();

    // Change the CWD to the repo root
    Directory.current = pathFromRepoRoot('');

    final from = argResults![_fromCommitArg] as String;
    final to = argResults![_toCommitArg] as String;
    print('Note: ensure you have gh installed and authenticated.');
    print('Finding all commmits between $from and $to');
    final result = await processManager.runProcess(
      CliCommand(
        'gh',
        [
          'api',
          'repos/flutter/flutter/compare/$from...$to',
          '--jq',
          '.commits[].sha',
        ],
      ),
    );
    final commits = result.stdout.split('\n').where((s) => s.isNotEmpty).toList();
    print('Found ${commits.length} commits.');

    var low = 0;
    var high = commits.length - 1;

    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final currentCommit = commits[mid];

      print('Bisecting commit: $currentCommit (${mid - low + 1} of ${high - low + 1})');

      await processManager.runProcess(
        CliCommand.tool(
          [
            'update-flutter-sdk',
            '--commit',
            currentCommit,
          ],
          toolScript: toolScript,
        ),
      );

      print('Running `flutter pub get`');
      await processManager.runProcess(
        CliCommand.flutter(['pub', 'get']),
      );
      final versionResult = await processManager.runProcess(
        CliCommand.flutter(['--version']),
      );
      print('Current flutter version:\n${versionResult.stdout}');
      print('Running flutter_binary_search.sh to check for the regression.');
      final bisectScriptPath = pathFromRepoRoot('tool/lib/commands/helpers/flutter_binary_search.sh');
      final testResult = await processManager.runProcess(
        CliCommand('bash', [bisectScriptPath], throwOnException: false),
      );

      if (testResult.exitCode == 0) {
        // The script passed, so the regression must be in a later commit.
        // This commit is the new "good" commit.
        print('flutter_binary_search.sh passed for commit $currentCommit.');
        low = mid + 1;
      } else {
        // The script failed, so the regression could be this commit or an
        // earlier one. This commit is the new "bad" commit.
        print('flutter_binary_search.sh failed for commit $currentCommit.');
        high = mid - 1;
      }
      print('\n');
    }

    // When the loop terminates, `low` will be the index of the first commit
    // in the list that failed.
    final firstBadCommit = commits[low];
    print('Binary search complete!');
    print('The first bad commit is: $firstBadCommit');
  }
}
