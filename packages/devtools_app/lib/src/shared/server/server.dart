// Copyright 2020 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:convert';

import 'package:devtools_shared/devtools_deeplink.dart';
import 'package:devtools_shared/devtools_extensions.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../development_helpers.dart';
import '../globals.dart';
import '../primitives/storage.dart';
import '../primitives/utils.dart';

part '_analytics_api.dart';
part '_app_size_api.dart';
part '_deep_links_api.dart';
part '_dtd_api.dart';
part '_extensions_api.dart';
part '_preferences_api.dart';
part '_release_notes_api.dart';
part '_server_api.dart';
part '_survey_api.dart';

final _log = Logger('devtools_server_client');

/// Whether the DevTools server is available so that the HTTP API can be used.
///
/// A value of `true` here does not necessarily mean the legacy SSE API is
/// available.
///
/// Since the DevTools server is a web server, it is only available for the
/// web platform.
///
/// TODO(dantup): Since this relates only to non-SSE API, it could be available
///  for non-web?
///
/// In `framework_initialize_web.dart`, we test the DevTools server connection
/// by pinging the server and checking the response. If this is successful, we
/// set the [storage] global to an instance of [ServerConnectionStorage].
bool get isDevToolsServerAvailable =>
    kIsWeb && storage is ServerConnectionStorage;

const _debugDevToolsServerEnvironmentVariable = String.fromEnvironment(
  'debug_devtools_server',
);

/// Whether DevTools was run using the `dt run` command, which runs DevTools in
/// debug mode using `flutter run` and connects it to an instance of the
/// DevTools server.
bool get usingDebugDevToolsServer =>
    _debugDevToolsServerEnvironmentVariable.isNotEmpty && !kReleaseMode;

String get devToolsServerUriAsString {
  // Ensure we only use the debug DevTools server URI in non-release
  // builds. By running `dt run`, an instance of DevTools run with `flutter run`
  // can be connected to the DevTools server on a different port.
  return usingDebugDevToolsServer
      ? _debugDevToolsServerEnvironmentVariable
      : Uri.base.toString();
}

/// Helper to build a request URI to the DevTools server, which may not be on
/// the same origin as the DevTools app window.
Uri buildDevToolsServerRequestUri(String url) {
  // [_debugDevToolsServerEnvironmentVariable] will be the empty string if the
  // [_debugDevToolsServerFlag] environment variable declaration was not set
  // using `--dart-define`.
  const baseUri = _debugDevToolsServerEnvironmentVariable;
  return Uri.parse(path.join(baseUri, url));
}

/// Helper to catch any server request which could fail.
///
/// Returns HttpRequest or null (if server failure).
Future<Response?> request(String url) async {
  Response? response;

  try {
    response = await post(buildDevToolsServerRequestUri(url));
  } catch (_) {}

  return response;
}

Future<DevToolsJsonFile?> requestFile({
  required String api,
  required String fileKey,
  required String filePath,
}) async {
  if (isDevToolsServerAvailable) {
    final url = Uri(path: api, queryParameters: {fileKey: filePath});
    final resp = await request(url.toString());
    if (resp?.statusOk ?? false) {
      return _devToolsJsonFileFromResponse(resp!, filePath);
    } else {
      logWarning(resp, api);
    }
  }
  return null;
}

Future<void> notifyForVmServiceConnection({
  required String vmServiceUri,
  required bool connected,
}) async {
  if (isDevToolsServerAvailable) {
    final uri = Uri(
      path: apiNotifyForVmServiceConnection,
      queryParameters: {
        apiParameterValueKey: vmServiceUri,
        apiParameterVmServiceConnected: connected.toString(),
      },
    );
    final resp = await request(uri.toString());
    final statusOk = resp?.statusOk ?? false;
    if (!statusOk) {
      logWarning(resp, apiNotifyForVmServiceConnection);
    }
  }
}

DevToolsJsonFile _devToolsJsonFileFromResponse(Response resp, String filePath) {
  final data = json.decode(resp.body) as Map;
  final lastModified = data['lastModifiedTime'];
  final lastModifiedTime = lastModified != null
      ? DateTime.parse(lastModified)
      : DateTime.now();
  return DevToolsJsonFile(
    name: filePath,
    lastModifiedTime: lastModifiedTime,
    data: data,
  );
}

void logWarning(Response? response, String apiType) {
  final respText = response?.body;
  _log.warning(
    'HttpRequest $apiType failed status = ${response?.statusCode}'
    '${respText.isNullOrEmpty ? '' : ', responseText = $respText'}',
  );
}

extension ResponseExtension on Response {
  bool get statusOk => statusCode == 200;
  bool get statusForbidden => statusCode == 403;
  bool get statusError => statusCode == 500;
}

class ServerConnectionStorage implements Storage {
  @override
  Future<String?> getValue(String key) async {
    final value = await getPreferenceValue(key);
    return value == null ? null : '$value';
  }

  @override
  Future<void> setValue(String key, String value) async {
    await setPreferenceValue(key, value);
  }
}
