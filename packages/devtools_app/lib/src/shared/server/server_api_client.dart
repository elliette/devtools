// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:convert';

import 'package:devtools_app_shared/ui.dart' show isEmbedded;
import 'package:devtools_shared/devtools_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../config_specific/notifications/notifications.dart';
import '../framework/framework_controller.dart';
import '../globals.dart';
import 'server.dart';

final _log = Logger('lib/src/shared/server_api_client');

/// This class coordinates the connection between the DevTools server and the
/// DevTools web app.
///
/// See `package:dds/src/devtools/client.dart`.
class DevToolsServerConnection {
  DevToolsServerConnection._(this.sseClient) {
    sseClient.stream!.listen((msg) {
      _handleMessage(msg);
    });
    initFrameworkController();
  }

  /// Returns a URI for the backend ./api folder for a DevTools page being hosted
  /// at `baseUri`. Trailing slashes are important to support Path-URL Strategy:
  ///
  /// - http://foo/devtools/ => http://foo/devtools/api
  /// - http://foo/devtools/inspector => http://foo/devtools/api
  ///
  /// For compatibility with any tools that might construct URIs ending with
  /// "/devtools" without the trailing slash, URIs ending with `devtools` (such
  /// as when hosted by DDS) are handled specially:
  ///
  /// - http://foo/devtools => http://foo/devtools/api
  @visibleForTesting
  static Uri apiUriFor(Uri baseUri) => baseUri.path.endsWith('devtools')
      ? baseUri.resolve('devtools/api/')
      : baseUri.resolve('api/');

  /// Connects to the legacy SSE API.
  ///
  /// Callers should first ensure the DevTools server is available (for example
  /// by calling [checkServerHttpApiAvailable] or verifying that it was
  /// successfull by using [isDevToolsServerAvailable])
  static Future<DevToolsServerConnection?> connect() async {
    // Don't connect SSE when running embedded because the API does not provide
    // anything that is used when embedded but it ties up one of the limited
    // number of connections to the server.
    // https://github.com/flutter/devtools/issues/8298
    if (isEmbedded()) {
      return null;
    }

    final serverUri = Uri.parse(devToolsServerUriAsString);
    final apiUri = apiUriFor(serverUri);
    final sseUri = apiUri.resolve('sse');
    final client = SseClient(sseUri.toString(), debugKey: 'DevToolsServer');
    return DevToolsServerConnection._(client);
  }

  final SseClient sseClient;

  int _nextRequestId = 0;
  Notification? _lastNotification;

  final _completers = <String, Completer<Object?>>{};

  /// Tie the DevTools server connection to the framework controller.
  ///
  /// This is called once, sometime after the `DevToolsServerConnection`
  /// instance is created.
  void initFrameworkController() {
    frameworkController.onConnected.listen((vmServiceUri) {
      _notifyConnected(vmServiceUri);
    });

    frameworkController.onPageChange.listen((page) {
      _notifyCurrentPage(page);
    });

    frameworkController.onDisconnected.listen((_) {
      _notifyDisconnected();
    });
  }

  Future<void> notify() async {
    final permission = await Notification.requestPermission();
    if (permission != 'granted') {
      return;
    }

    // Dismiss any earlier notifications first so they don't build up in the
    // notifications list if the user presses the button multiple times.
    dismissNotifications();

    _lastNotification = Notification(
      'Dart DevTools',
      body: 'DevTools is available in this existing browser window',
    );
  }

  void dismissNotifications() {
    _lastNotification?.close();
  }

  Future<T> _callMethod<T>(String method, [Map<String, dynamic>? params]) {
    final id = '${_nextRequestId++}';
    final json = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    final completer = Completer<T>();
    _completers[id] = completer;
    sseClient.sink!.add(json);
    return completer.future;
  }

  void _handleMessage(String msg) {
    try {
      final Map request = jsonDecode(msg);

      if (request.containsKey('method')) {
        final String method = request['method'];
        final Map<String, dynamic> params = request['params'] ?? {};
        _handleMethod(method, params);
      } else if (request.containsKey('id')) {
        _handleResponse(request['id']!, request['result']);
      } else {
        _log.info('Unable to parse API message from server:\n\n$msg');
      }
    } catch (e) {
      _log.info('Failed to handle API message from server:\n\n$msg\n\n$e');
    }
  }

  void _handleMethod(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'connectToVm':
        final String uri = params['uri'];
        final notify = params['notify'] == true;
        frameworkController.notifyConnectToVmEvent(
          Uri.parse(uri),
          notify: notify,
        );
        return;
      case 'showPage':
        final String pageId = params['page'];
        frameworkController.notifyShowPageId(pageId);
        return;
      case 'enableNotifications':
        unawaited(Notification.requestPermission());
        return;
      case 'notify':
        unawaited(notify());
        return;
      case 'ping':
        ping();
        return;
      default:
        _log.info('Unknown request $method from server');
    }
  }

  void _handleResponse(String id, Object? result) {
    final completer = _completers.remove(id);
    completer?.complete(result);
  }

  void _notifyConnected(String vmServiceUri) {
    unawaited(_callMethod('connected', {'uri': vmServiceUri}));
  }

  void _notifyCurrentPage(PageChangeEvent page) {
    unawaited(
      _callMethod('currentPage', {
        'id': page.id,
        // TODO(kenz): see if we need to change the client code on the
        // DevTools server to be aware of the type of embedded mode (many vs.
        // one).
        'embedded': page.embedMode.embedded,
      }),
    );
  }

  void _notifyDisconnected() {
    unawaited(_callMethod('disconnected'));
  }

  /// Allows the server to ping the client to see that it is definitely still
  /// active and doesn't just appear to be connected because of SSE timeouts.
  void ping() {
    unawaited(_callMethod('pingResponse'));
  }
}
