// Copyright 2018 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'test_utils.dart';

class AppFixture {
  AppFixture._(
    this.process,
    this.lines,
    this.serviceUri,
    this.serviceConnection,
    this.isolates,
    this.onTeardown,
  ) {
    // "starting app"
    _onAppStarted = lines.first;

    unawaited(serviceConnection.streamListen(EventStreams.kIsolate));
    _isolateEventStreamSubscription =
        serviceConnection.onIsolateEvent.listen((Event event) {
      if (event.kind == EventKind.kIsolateExit) {
        isolates.remove(event.isolate);
      } else {
        if (!isolates.contains(event.isolate)) {
          isolates.add(event.isolate);
        }
      }
    });
  }

  final Process process;
  final Stream<String> lines;
  final Uri serviceUri;
  final VmService serviceConnection;
  final List<IsolateRef?> isolates;
  late final StreamSubscription<Event> _isolateEventStreamSubscription;
  final Future<void> Function()? onTeardown;
  late Future<void> _onAppStarted;

  Future<void> get onAppStarted => _onAppStarted;

  IsolateRef? get mainIsolate => isolates.firstOrNull;

  Future<Response> invoke(String expression) async {
    final isolateRef = mainIsolate!;
    final isolateId = isolateRef.id!;
    final isolate = await serviceConnection.getIsolate(isolateId);

    return await serviceConnection.evaluate(
      isolateId,
      isolate.rootLib!.id!,
      expression,
    );
  }

  Future<void> teardown() async {
    if (onTeardown != null) {
      await onTeardown!();
    }
    await _isolateEventStreamSubscription.cancel();
    await serviceConnection.dispose();
    process.kill();
  }
}

// This is the fixture for Dart CLI applications.
class CliAppFixture extends AppFixture {
  CliAppFixture._(
    this.appScriptPath,
    Process process,
    Stream<String> lines,
    Uri serviceUri,
    VmService serviceConnection,
    List<IsolateRef> isolates,
    Future<void> Function()? onTeardown,
  ) : super._(
          process,
          lines,
          serviceUri,
          serviceConnection,
          isolates,
          onTeardown,
        );

  final String appScriptPath;

  static Future<CliAppFixture> create(String appScriptPath) async {
    final dartVmServicePrefix =
        RegExp('(Observatory|The Dart VM service is) listening on ');

    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>['--observe=0', '--pause-isolates-on-start', appScriptPath],
    );

    final Stream<String> lines =
        process.stdout.transform(utf8.decoder).transform(const LineSplitter());
    final lineController = StreamController<String>.broadcast();
    final completer = Completer<String>();

    final linesSubscription = lines.listen((String line) {
      if (completer.isCompleted) {
        lineController.add(line);
      } else if (line.contains(dartVmServicePrefix)) {
        completer.complete(line);
      } else {
        // Often something like:
        // "Waiting for another flutter command to release the startup lock...".
        print(line);
      }
    });

    // Observatory listening on http://127.0.0.1:9595/(token)
    final observatoryText = await completer.future;
    final observatoryUri = observatoryText.replaceAll(dartVmServicePrefix, '');
    var uri = Uri.parse(observatoryUri);

    if (!uri.isAbsolute) {
      throw 'Could not parse VM Service URI: "$observatoryText"';
    }

    // Map to WS URI.
    uri = convertToWebSocketUrl(serviceProtocolUrl: uri);

    final serviceConnection = await vmServiceConnectUri(uri.toString());

    final vm = await serviceConnection.getVM();

    final isolate = await _waitForIsolate(serviceConnection, 'PauseStart');
    await serviceConnection.resume(isolate.id!);

    Future<void> onTeardown() async {
      await linesSubscription.cancel();
      await lineController.close();
    }

    return CliAppFixture._(
      appScriptPath,
      process,
      lineController.stream,
      uri,
      serviceConnection,
      vm.isolates!,
      onTeardown,
    );
  }

  static Future<Isolate> _waitForIsolate(
    VmService serviceConnection,
    String pauseEventKind,
  ) async {
    Isolate? foundIsolate;
    await waitFor(() async {
      const skipId = 'skip';
      final vm = await serviceConnection.getVM();
      final isolates = await vm.isolates!
          .map((ref) => serviceConnection
                  .getIsolate(ref.id!)
                  // Calling getIsolate() can sometimes return a collected sentinel
                  // for an isolate that hasn't started yet. We can just ignore these
                  // as on the next trip around the Isolate will be returned.
                  // https://github.com/dart-lang/sdk/issues/33747
                  .catchError((Object error) {
                print('getIsolate(${ref.id}) failed, skipping\n$error');
                return Future<Isolate>.value(Isolate(id: skipId));
              }))
          .wait;
      foundIsolate = isolates.firstWhereOrNull(
        (isolate) =>
            isolate.id != skipId && isolate.pauseEvent?.kind == pauseEventKind,
      );
      return foundIsolate != null;
    });
    return foundIsolate!;
  }

  String get scriptSource {
    return File(appScriptPath).readAsStringSync();
  }

  static List<int> parseBreakpointLines(String source) {
    return _parseLines(source, 'breakpoint');
  }

  static List<int> parseSteppingLines(String source) {
    return _parseLines(source, 'step');
  }

  static List<int> parseExceptionLines(String source) {
    return _parseLines(source, 'exception');
  }

  static List<int> _parseLines(String source, String keyword) {
    final lines = source.replaceAll('\r', '').split('\n');
    final matches = <int>[];

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].endsWith('// $keyword')) {
        matches.add(i);
      }
    }

    return matches;
  }
}
