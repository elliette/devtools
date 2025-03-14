// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _log = Logger('dtd_manager');

/// Manages a connection to the Dart Tooling Daemon.
class DTDManager {
  ValueListenable<DartToolingDaemon?> get connection => _connection;
  final _connection = ValueNotifier<DartToolingDaemon?>(null);

  DartToolingDaemon get _dtd => _connection.value!;

  /// Whether the [DTDManager] is connected to a running instance of the DTD.
  bool get hasConnection => connection.value != null;

  /// The URI of the current DTD connection.
  Uri? get uri => _uri;
  Uri? _uri;

  // Subscripton that listens for the [done] event.
  StreamSubscription<void>? _connectionClosedSubscription;


  bool _shouldAttemptReconnection = true;

  /// Sets the Dart Tooling Daemon connection to point to [uri].
  ///
  /// Before connecting to [uri], if a current connection exists, then
  /// [disconnect] is called to close it.
  Future<void> connect(
    Uri uri, {
    void Function(Object, StackTrace?)? onError,
  }) async {
    await disconnect();
    try {
      final dtdConnection = await DartToolingDaemon.connect(uri);
      _connection.value = dtdConnection;
      _shouldAttemptReconnection = true;
      _subscribeToConnectionClosed(dtdConnection);

      dtdConnection.clientDone.whenComplete(() => _log.info('!!!!!!!!!!!!! DTD CLIENT CLOSED!!!!!!!!'));
      dtdConnection.serverDone.whenComplete(() => _log.info('!!!!!!!!!!!!!! DTD SERVER CLOSED!!!!!!!!'));
      _uri = uri;
      _log.info(
          '[${DateTime.now().toIso8601String()}]  Successfully connected to DTD at: $uri');
    } catch (e, st) {
      onError?.call(e, st);
    }
  }

  void _subscribeToConnectionClosed(DartToolingDaemon dtdConnection) {
    _log.info('[${DateTime.now().toIso8601String()}] Subscribe to connection closed, should attempt reconnection? $_shouldAttemptReconnection');
    if (_shouldAttemptReconnection) {
      _connectionClosedSubscription = Stream.fromFuture(dtdConnection.done)
          .listen(_attemptDtdReconnection,
              onError: (error) {
                _log.info('Error from DTD closed subscription: $error');
              },
              onDone: () => _subscribeToConnectionClosed(dtdConnection));
    }
  }

  Future<void> _attemptDtdReconnection(void _) async {
    _log.info(
        '[${DateTime.now().toIso8601String()}] ATTEMPTING RECONNECTION TO THE DART TOOLING DAEMON...');
    if (uri != null) {
      await connect(
        uri!,
        onError: (e, st) {
          _log.info(
              '[${DateTime.now().toIso8601String()}] FAILED TO RECONNECT TO THE DART TOOLING DAEMON');
        },
      );
    } else {
      await _cancelConnectionClosedSubscription();
    }
  }

  Future<void> _cancelConnectionClosedSubscription() async {
    await _connectionClosedSubscription?.cancel();
    _connectionClosedSubscription = null;
  }

  /// Closes and unsets the Dart Tooling Daemon connection, if one is set.
  Future<void> disconnect() async {
    _shouldAttemptReconnection = false;
    await _cancelConnectionClosedSubscription();

    if (_connection.value != null) {
      await _connection.value!.close();
    }

    _connection.value = null;
    _uri = null;
    _workspaceRoots = null;
    _projectRoots = null;
  }

  Future<void> dispose() async {
    await disconnect();
    _connection.dispose();
  }

  /// Returns the workspace roots for the Dart Tooling Daemon connection.
  ///
  /// These roots are set by the tool that started DTD, which may be the IDE,
  /// DevTools server, or DDS (the Dart Development Service managed by the Dart
  /// or Flutter CLI tools).
  ///
  /// A workspace root is considered any directory that is at the root of the
  /// IDE's open project or workspace, or in the case where the Dart Tooling
  /// Daemon was started from the DevTools server or DDS (e.g. an app ran from
  /// the CLI), a workspace root is the root directory for the Dart or Flutter
  /// program connected to DevTools.
  ///
  /// By default, the cached value [_workspaceRoots] will be returned when
  /// available. When [forceRefresh] is true, the cached value will be cleared
  /// and recomputed.
  Future<IDEWorkspaceRoots?> workspaceRoots({bool forceRefresh = false}) async {
    if (!hasConnection) return null;
    if (_workspaceRoots != null && forceRefresh) {
      _workspaceRoots = null;
    }
    try {
      return _workspaceRoots ??= await _dtd.getIDEWorkspaceRoots();
    } catch (e) {
      _log.fine('Error fetching IDE workspaceRoots: $e');
      return null;
    }
  }

  IDEWorkspaceRoots? _workspaceRoots;

  /// Returns the project roots for the Dart Tooling Daemon connection.
  ///
  /// A project root is any directory, contained within the current set of
  /// [workspaceRoots], that contains a 'pubspec.yaml' file.
  ///
  /// By default, the cached value [_projectRoots] will be returned when
  /// available. When [forceRefresh] is true, the cached value will be cleared
  /// and recomputed.
  ///
  /// [depth] is the maximum depth that each workspace root directory tree will
  /// will be searched for project roots. Setting [depth] to a large number
  /// may have performance implications when traversing large trees.
  Future<UriList?> projectRoots({
    int? depth = defaultGetProjectRootsDepth,
    bool forceRefresh = false,
  }) async {
    if (!hasConnection) return null;
    if (_projectRoots != null && forceRefresh) {
      _projectRoots = null;
    }
    try {
      return _projectRoots ??= await _dtd.getProjectRoots(depth: depth!);
    } catch (e) {
      _log.fine('Error fetching project roots: $e');
      return null;
    }
  }

  UriList? _projectRoots;
}
