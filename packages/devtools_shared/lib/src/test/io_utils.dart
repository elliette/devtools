// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// The directory used to store per-user settings for Dart tooling.
Directory getDartPrefsDirectory() {
  return Directory(path.join(getUserHomeDir(), '.dart'));
}

/// Return the user's home directory.
String getUserHomeDir() {
  final envKey = Platform.operatingSystem == 'windows' ? 'APPDATA' : 'HOME';
  final value = Platform.environment[envKey];
  return value ?? '.';
}

Stream<String> transformToLines(Stream<List<int>> byteStream) {
  return byteStream
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter());
}

mixin IOMixin {
  static const killTimeout = Duration(seconds: 10);

  final stdoutController = StreamController<String>.broadcast();

  final stderrController = StreamController<String>.broadcast();

  final streamSubscriptions = <StreamSubscription<String>>[];

  void listenToProcessOutput(
    Process process, {
    void Function(String)? onStdout,
    void Function(String)? onStderr,
    void Function(String)? printCallback,
    String printTag = '',
  }) {
    printCallback =
        printCallback ?? (line) => _defaultPrintCallback(line, tag: printTag);

    streamSubscriptions.addAll([
      transformToLines(process.stdout).listen((String line) {
        onStdout?.call(line);
        stdoutController.add(line);
      }),
      transformToLines(process.stderr).listen((String line) {
        onStderr?.call(line);
        stderrController.add(line);
      }),

      // This is just debug printing to aid running/debugging tests locally.
      stdoutController.stream.listen(printCallback),
      stderrController.stream.listen(printCallback),
    ]);
  }

  Future<void> cancelAllStreamSubscriptions() async {
    await streamSubscriptions.map((s) => s.cancel()).wait;
    await [
      stdoutController.close(),
      stderrController.close(),
    ].wait;
    streamSubscriptions.clear();
  }

  static void _defaultPrintCallback(String line, {String tag = ''}) {
    print(tag.isNotEmpty ? '$tag - $line' : line);
  }

  Future<int> killGracefully(
    Process process, {
    bool debugLogging = false,
  }) async {
    final processId = process.pid;
    if (debugLogging) {
      print(
        '${DateTime.now()}: Cancelling all stream subscriptions for process '
        '$processId before killing.',
      );
    }
    await cancelAllStreamSubscriptions();
    if (debugLogging) {
      print('${DateTime.now()}: Sending SIGTERM to $processId.');
    }
    Process.killPid(processId);
    return process.exitCode.timeout(
      killTimeout,
      onTimeout: () => _killForcefully(process, debugLogging: debugLogging),
    );
  }

  Future<int> _killForcefully(
    Process process, {
    bool debugLogging = false,
  }) {
    final processId = process.pid;
    // Use sigint here instead of sigkill. See
    // https://github.com/flutter/flutter/issues/117415.
    if (debugLogging) {
      print('${DateTime.now()}: Sending SIGINT to $processId.');
    }
    Process.killPid(processId, ProcessSignal.sigint);
    return process.exitCode;
  }
}
