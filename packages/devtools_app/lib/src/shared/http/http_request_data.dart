// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:vm_service/vm_service.dart';

import '../../screens/network/network_model.dart';
import '../globals.dart';
import '../primitives/utils.dart';
import 'constants.dart';
import 'http.dart';

final _log = Logger('http_request_data');

/// Used to represent an instant event emitted during an HTTP request.
class DartIOHttpInstantEvent {
  DartIOHttpInstantEvent._(this._event);

  final HttpProfileRequestEvent _event;

  String get name => _event.event;

  /// The time the instant event was recorded.
  DateTime get timestamp => _event.timestamp;

  /// The amount of time since the last instant event completed.
  TimeRange get timeRange => _timeRangeBuilder.build();

  // This is modified from within HttpRequestData.
  final TimeRangeBuilder _timeRangeBuilder = TimeRangeBuilder();
}

/// An abstraction of an HTTP request made through dart:io.
class DartIOHttpRequestData extends NetworkRequest {
  DartIOHttpRequestData(
    this._request, {
    bool requestFullDataFromVmService = true,
  }) {
    if (requestFullDataFromVmService && _request.isResponseComplete) {
      unawaited(getFullRequestData());
    }
  }

  factory DartIOHttpRequestData.fromJson(
    Map<String, Object?> modifiedRequestData,
    Map<String, Object?>? requestPostData,
    Map<String, Object?>? responseContent,
  ) {
    final isFullRequest =
        modifiedRequestData.containsKey(HttpRequestDataKeys.requestBody.name) &&
        modifiedRequestData.containsKey(HttpRequestDataKeys.responseBody.name);

    final parsedRequest = isFullRequest
        ? HttpProfileRequest.parse(modifiedRequestData)
        : HttpProfileRequestRef.parse(modifiedRequestData);

    final responseBody = responseContent?[HttpRequestDataKeys.text.name]
        ?.toString();
    final requestBody = requestPostData?[HttpRequestDataKeys.text.name]
        ?.toString();

    return DartIOHttpRequestData(
        parsedRequest!,
        requestFullDataFromVmService: parsedRequest is! HttpProfileRequest,
      )
      .._responseBody = responseBody
      .._requestBody = requestBody;
  }

  @override
  Map<String, Object?> toJson() {
    return {
      HttpRequestDataKeys.request.name: (_request as HttpProfileRequest)
          .toJson(),
    };
  }

  static const _connectionInfoKey = 'connectionInfo';
  static const _contentTypeKey = 'content-type';
  static const _localPortKey = 'localPort';

  HttpProfileRequestRef _request;

  bool isFetchingFullData = false;

  Future<void> getFullRequestData() async {
    try {
      if (isFetchingFullData) return; // We are already fetching
      isFetchingFullData = true;
      if (serviceConnection.serviceManager.connectedState.value.connected) {
        final updated = await serviceConnection.serviceManager.service!
            .getHttpProfileRequestWrapper(
              _request.isolateId,
              _request.id.toString(),
            );
        _request = updated;
        final fullRequest = _request as HttpProfileRequest;
        _responseBody = utf8.decode(fullRequest.responseBody!);
        _requestBody = utf8.decode(fullRequest.requestBody!);
        notifyListeners();
      }
    } finally {
      isFetchingFullData = false;
    }
  }

  static List<Cookie> _parseCookies(List<String>? cookies) {
    if (cookies == null) return [];
    return cookies.map((cookie) => Cookie.fromSetCookieValue(cookie)).toList();
  }

  @override
  String get id => _request.id;

  bool get _hasError => _request.request?.hasError ?? false;

  DateTime? get _endTime =>
      _hasError ? _request.endTime : _request.response?.endTime;

  @override
  Duration? get duration {
    if (inProgress || !isValid) return null;
    // Timestamps are in microseconds
    return _endTime!.difference(_request.startTime);
  }

  /// Whether the request is safe to display in the UI.
  ///
  /// The dart:io HTTP profiling service extensions should never return invalid
  /// requests.
  bool get isValid => true;

  /// A map of general information associated with an HTTP request.
  Map<String, dynamic> get general {
    return {
      'method': _request.method,
      'uri': _request.uri.toString(),
      if (!didFail) ...{
        'connectionInfo': _request.request?.connectionInfo,
        'contentLength': _request.request?.contentLength,
      },
      if (_request.response != null) ...{
        'compressionState': _request.response!.compressionState,
        'isRedirect': _request.response!.isRedirect,
        'persistentConnection': _request.response!.persistentConnection,
        'reasonPhrase': _request.response!.reasonPhrase,
        'redirects': _request.response!.redirects,
        'statusCode': _request.response!.statusCode,
        'queryParameters': _request.uri.queryParameters,
      },
    };
  }

  @override
  String? get contentType {
    final headers = responseHeaders;
    if (headers == null || headers[_contentTypeKey] == null) {
      return null;
    }
    return headers[_contentTypeKey].toString();
  }

  @override
  String get type {
    const defaultType = 'http';
    var mime = contentType;
    if (mime == null) {
      return defaultType;
    }

    // Extract the MIME from `contentType`.
    // Example: "[text/html; charset-UTF-8]" --> "text/html"
    mime = mime.split(';').first;
    if (mime.startsWith('[')) {
      mime = mime.substring(1);
    }
    if (mime.endsWith(']')) {
      mime = mime.substring(0, mime.length - 1);
    }
    return _extensionFromMime(mime) ?? defaultType;
  }

  /// Extracts the extension from [mime], with overrides for shortened
  /// extensions of common types (e.g., jpe -> jpeg).
  String? _extensionFromMime(String mime) {
    final ext = extensionFromMime(mime);
    if (ext == 'jpe') {
      return 'jpeg';
    }
    if (ext == 'htm') {
      return 'html';
    }
    // text/plain -> conf
    if (ext == 'conf') {
      return 'txt';
    }
    return ext;
  }

  @override
  String get method => _request.method;

  @override
  int? get port {
    final Map<String, dynamic>? connectionInfo = general[_connectionInfoKey];
    return connectionInfo != null ? connectionInfo[_localPortKey] : null;
  }

  /// True if the HTTP request hasn't completed yet, determined by the lack of
  /// an end time in the response data.
  @override
  bool get inProgress =>
      _hasError ? !_request.isRequestComplete : !_request.isResponseComplete;

  /// All instant events logged to the timeline for this HTTP request.
  List<DartIOHttpInstantEvent> get instantEvents {
    if (_instantEvents == null) {
      _instantEvents = _request.events
          .map((e) => DartIOHttpInstantEvent._(e))
          .toList();
      _recalculateInstantEventTimes();
    }
    return _instantEvents!;
  }

  List<DartIOHttpInstantEvent>? _instantEvents;

  /// True if either the request or response contained cookies.
  bool get hasCookies =>
      requestCookies.isNotEmpty || responseCookies.isNotEmpty;

  /// A list of all cookies contained within the request headers.
  List<Cookie> get requestCookies => _hasError
      ? []
      : DartIOHttpRequestData._parseCookies(_request.request?.cookies);

  /// A list of all cookies contained within the response headers.
  List<Cookie> get responseCookies =>
      DartIOHttpRequestData._parseCookies(_request.response?.cookies);

  /// The request headers for the HTTP request.
  Map<String, dynamic>? get requestHeaders =>
      _hasError ? null : _request.request?.headers;

  /// The response headers for the HTTP request.
  Map<String, dynamic>? get responseHeaders => _request.response?.headers;

  /// The query parameters for the request.
  Map<String, dynamic>? get queryParameters => _request.uri.queryParameters;

  @override
  bool get didFail {
    if (status == null) return false;
    if (status == 'Error') return true;

    try {
      final code = int.parse(status!);
      // Status codes 400-499 are client errors and 500-599 are server errors.
      if (code >= 400) {
        return true;
      }
    } on Exception catch (e, st) {
      _log.shout('Could not parse HTTP request status: $status', e, st);
      return true;
    }
    return false;
  }

  /// Merges the information from another [DartIOHttpRequestData] into this
  /// instance.
  void merge(DartIOHttpRequestData data) {
    _request = data._request;
    notifyListeners();
  }

  @override
  DateTime? get endTimestamp => _endTime;

  @override
  DateTime get startTimestamp => _request.startTime;

  @override
  String? get status =>
      _hasError ? 'Error' : _request.response?.statusCode.toString();

  @override
  String get uri => _request.uri.toString();

  String? get responseBody {
    if (_request is! HttpProfileRequest) {
      return null;
    }
    final fullRequest = _request as HttpProfileRequest;
    try {
      if (!_request.isResponseComplete) return null;
      if (_responseBody != null) return _responseBody;
      _responseBody = utf8.decode(fullRequest.responseBody!);
      return _responseBody;
    } on FormatException {
      return '<binary data>';
    }
  }

  Uint8List? get encodedResponse {
    if (!_request.isResponseComplete) return null;
    final fullRequest = _request as HttpProfileRequest;
    return fullRequest.responseBody;
  }

  String? _responseBody;

  String? get requestBody {
    if (_request is! HttpProfileRequest) {
      return null;
    }
    final fullRequest = _request as HttpProfileRequest;
    try {
      if (!_request.isResponseComplete) return null;
      final acceptedMethods = {'POST', 'PUT', 'PATCH'};
      if (!acceptedMethods.contains(_request.method)) return null;
      if (_requestBody != null) return _requestBody;
      if (fullRequest.requestBody == null) return null;
      _requestBody = utf8.decode(fullRequest.requestBody!);
      return _requestBody;
    } on FormatException {
      return '<binary data>';
    }
  }

  String? _requestBody;

  void _recalculateInstantEventTimes() {
    DateTime lastTime = _request.startTime;
    for (final instant in instantEvents) {
      final instantTime = instant.timestamp;
      instant._timeRangeBuilder
        ..start = lastTime.microsecondsSinceEpoch
        ..end = instantTime.microsecondsSinceEpoch;
      lastTime = instantTime;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is DartIOHttpRequestData && id == other.id && super == other;
  }

  @override
  int get hashCode =>
      Object.hash(id, method, uri, contentType, type, port, startTimestamp);
}

extension HttpRequestExtension on List<DartIOHttpRequestData> {
  List<HttpProfileRequest> get mapToHttpProfileRequests {
    return map(
      (httpRequestData) => httpRequestData._request as HttpProfileRequest,
    ).toList();
  }
}

extension HttpProfileRequestExtension on HttpProfileRequest {
  Map<String, Object?> toJson() {
    return {
      HttpRequestDataKeys.id.name: id,
      HttpRequestDataKeys.method.name: method,
      HttpRequestDataKeys.uri.name: uri.toString(),
      HttpRequestDataKeys.startTime.name: startTime.microsecondsSinceEpoch,
      HttpRequestDataKeys.endTime.name: endTime?.microsecondsSinceEpoch,
      HttpRequestDataKeys.response.name: response?.toJson(),
      HttpRequestDataKeys.request.name: request?.toJson(),
      HttpRequestDataKeys.isolateId.name: isolateId,
      HttpRequestDataKeys.events.name: events.map((e) => e.toJson()).toList(),
      HttpRequestDataKeys.requestBody.name: requestBody?.toList(),
      HttpRequestDataKeys.responseBody.name: responseBody?.toList(),
    };
  }
}

extension HttpProfileRequestDataExtension on HttpProfileRequestData {
  Map<String, Object?> toJson() {
    final jsonMap = <String, Object?>{};
    try {
      jsonMap[HttpRequestDataKeys.headers.name] = headers ?? {};
      jsonMap[HttpRequestDataKeys.followRedirects.name] = followRedirects;
      jsonMap[HttpRequestDataKeys.maxRedirects.name] = maxRedirects;
      jsonMap[HttpRequestDataKeys.connectionInfo.name] = connectionInfo;
      jsonMap[HttpRequestDataKeys.contentLength.name] = contentLength;
      jsonMap[HttpRequestDataKeys.cookies.name] = cookies ?? [];
      jsonMap[HttpRequestDataKeys.persistentConnection.name] =
          persistentConnection;
      jsonMap[HttpRequestDataKeys.proxyDetails.name] = proxyDetails?.toJson();
    } catch (e, st) {
      _log.shout('Error serializing HttpProfileRequestData', e, st);
      jsonMap[HttpRequestDataKeys.error.name] =
          error ?? 'Serialization failed: $e';
    }
    return jsonMap;
  }
}

extension HttpProfileResponseDataExtension on HttpProfileResponseData {
  Map<String, Object?> toJson() {
    final jsonMap = <String, Object?>{};
    try {
      jsonMap[HttpRequestDataKeys.startTime.name] =
          startTime?.microsecondsSinceEpoch;
      jsonMap[HttpRequestDataKeys.endTime.name] =
          endTime?.microsecondsSinceEpoch;
      jsonMap[HttpRequestDataKeys.headers.name] = headers ?? {};
      jsonMap[HttpRequestDataKeys.compressionState.name] = compressionState;
      jsonMap[HttpRequestDataKeys.connectionInfo.name] = connectionInfo;
      jsonMap[HttpRequestDataKeys.contentLength.name] = contentLength;
      jsonMap[HttpRequestDataKeys.cookies.name] = cookies ?? [];
      jsonMap[HttpRequestDataKeys.isRedirect.name] = isRedirect;
      jsonMap[HttpRequestDataKeys.persistentConnection.name] =
          persistentConnection;
      jsonMap[HttpRequestDataKeys.reasonPhrase.name] = reasonPhrase;
      jsonMap[HttpRequestDataKeys.redirects.name] = redirects;
      jsonMap[HttpRequestDataKeys.statusCode.name] = statusCode;
    } catch (e, st) {
      _log.shout('Error serializing HttpProfileResponseData', e, st);
      jsonMap[HttpRequestDataKeys.error.name] =
          error ?? 'Serialization failed: $e';
    }
    return jsonMap;
  }
}

extension HttpProfileRequestEventExtension on HttpProfileRequestEvent {
  Map<String, Object?> toJson() {
    return {
      HttpRequestDataKeys.event.name: event,
      HttpRequestDataKeys.timestamp.name: timestamp.microsecondsSinceEpoch,
      HttpRequestDataKeys.arguments.name: arguments,
    };
  }
}

extension HttpProfileProxyDataExtension on HttpProfileProxyData {
  Map<String, Object?> toJson() {
    return {
      HttpRequestDataKeys.host.name: host,
      HttpRequestDataKeys.username.name: username,
      HttpRequestDataKeys.isDirect.name: isDirect,
      HttpRequestDataKeys.host.name: port,
    };
  }
}
