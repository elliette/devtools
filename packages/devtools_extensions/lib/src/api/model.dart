// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'api.dart';

/// Data model for a devtools extension event that will be sent and received
/// over 'postMessage' between DevTools and an embedded extension iFrame.
///
/// See [DevToolsExtensionEventType] for different types of events that are
/// supported over this communication channel.
class DevToolsExtensionEvent {
  DevToolsExtensionEvent(
    this.type, {
    this.data,
    this.source,
  });

  factory DevToolsExtensionEvent.parse(Map<String, Object?> json) {
    final eventType =
        DevToolsExtensionEventType.from(json[_typeKey]! as String);
    final data = (json[_dataKey] as Map?)?.cast<String, Object?>();
    final source = json[sourceKey] as String?;
    return DevToolsExtensionEvent(eventType, data: data, source: source);
  }

  static DevToolsExtensionEvent? tryParse(Object data) {
    try {
      final dataAsMap = (data as Map).cast<String, Object?>();
      return DevToolsExtensionEvent.parse(dataAsMap);
    } catch (_) {
      return null;
    }
  }

  static const _typeKey = 'type';
  static const _dataKey = 'data';
  static const sourceKey = 'source';

  final DevToolsExtensionEventType type;
  final Map<String, Object?>? data;

  /// Optional field to describe the source that created and sent this event.
  final String? source;

  Map<String, Object?> toJson() {
    return {
      _typeKey: type.name,
      if (data != null) _dataKey: data!,
    };
  }

  @override
  String toString() {
    return '[$type, data: ${data.toString()}'
        '${source != null ? ', source: $source' : ''}]';
  }
}

/// A void callback that handles a [DevToolsExtensionEvent].
typedef ExtensionEventHandler = void Function(DevToolsExtensionEvent event);

/// An extension event of type [DevToolsExtensionEventType.showNotification]
/// that is sent from an extension to DevTools asking DevTools to post a
/// notification the the DevTools notification framework.
class ShowNotificationExtensionEvent extends DevToolsExtensionEvent {
  ShowNotificationExtensionEvent({required String message})
      : super(
          DevToolsExtensionEventType.showNotification,
          data: {_messageKey: message},
        );

  factory ShowNotificationExtensionEvent.from(DevToolsExtensionEvent event) {
    assert(event.type == DevToolsExtensionEventType.showNotification);
    final message = event.data!.checkValid<String>(_messageKey);
    return ShowNotificationExtensionEvent(message: message);
  }

  static const _messageKey = 'message';

  String get message => data![_messageKey] as String;
}

/// An extension event of type [DevToolsExtensionEventType.showBannerMessage]
/// that is sent from an extension to DevTools asking DevTools to post a
/// banner message to the extension's screen using the DevTools banner message
/// framework.
class ShowBannerMessageExtensionEvent extends DevToolsExtensionEvent {
  ShowBannerMessageExtensionEvent({
    required String id,
    required String bannerMessageType,
    required String message,
    required String extensionName,
    bool ignoreIfAlreadyDismissed = true,
    bool dismissOnConnectionChanges = true,
  })  : assert(bannerMessageType == 'warning' || bannerMessageType == 'error'),
        super(
          DevToolsExtensionEventType.showBannerMessage,
          data: {
            _idKey: id,
            _bannerMessageTypeKey: bannerMessageType,
            _messageKey: message,
            _extensionNameKey: extensionName,
            _ignoreIfAlreadyDismissedKey: ignoreIfAlreadyDismissed,
            _dismissOnConnectionChangesKey: dismissOnConnectionChanges,
          },
        );

  factory ShowBannerMessageExtensionEvent.from(DevToolsExtensionEvent event) {
    assert(event.type == DevToolsExtensionEventType.showBannerMessage);
    final eventData = event.data!;
    final id = eventData.checkValid<String>(_idKey);
    final message = eventData.checkValid<String>(_messageKey);
    final type = eventData.checkValid<String>(_bannerMessageTypeKey);
    final extensionName = eventData.checkValid<String>(_extensionNameKey);
    final ignoreIfAlreadyDismissed =
        (eventData[_ignoreIfAlreadyDismissedKey] as bool?) ?? true;
    final dismissOnConnectionChanges =
        (eventData[_dismissOnConnectionChangesKey] as bool?) ?? true;
    return ShowBannerMessageExtensionEvent(
      id: id,
      bannerMessageType: type,
      message: message,
      extensionName: extensionName,
      ignoreIfAlreadyDismissed: ignoreIfAlreadyDismissed,
      dismissOnConnectionChanges: dismissOnConnectionChanges,
    );
  }

  static const _messageKey = 'message';
  static const _idKey = 'id';
  static const _bannerMessageTypeKey = 'bannerMessageType';
  static const _extensionNameKey = 'extensionName';
  static const _ignoreIfAlreadyDismissedKey = 'ignoreIfAlreadyDismissed';
  static const _dismissOnConnectionChangesKey = 'dismissOnConnectionChanges';

  String get messageId => data![_idKey] as String;
  String get bannerMessageType => data![_bannerMessageTypeKey] as String;
  String get message => data![_messageKey] as String;
  String get extensionName => data![_extensionNameKey] as String;
  bool get ignoreIfAlreadyDismissed =>
      (data![_ignoreIfAlreadyDismissedKey] as bool?) ?? true;

  /// Whether this message should be dismissed on app connection changes.
  bool get dismissOnConnectionChanges =>
      (data![_dismissOnConnectionChangesKey] as bool?) ?? true;
}

/// An extension event of type [DevToolsExtensionEventType.copyToClipboard]
/// that is sent from an extension to DevTools asking DevTools copy content to
/// the user's clipboard.
class CopyToClipboardExtensionEvent extends DevToolsExtensionEvent {
  CopyToClipboardExtensionEvent({
    required String content,
    String successMessage = defaultSuccessMessage,
  }) : super(
          DevToolsExtensionEventType.copyToClipboard,
          data: {
            _contentKey: content,
            _successMessageKey: successMessage,
          },
        );

  factory CopyToClipboardExtensionEvent.from(DevToolsExtensionEvent event) {
    assert(event.type == DevToolsExtensionEventType.copyToClipboard);
    final content = event.data!.checkValid<String>(_contentKey);
    final successMessage = event.data!.checkValid<String>(_successMessageKey);
    return CopyToClipboardExtensionEvent(
      content: content,
      successMessage: successMessage,
    );
  }

  static const _contentKey = 'content';
  static const _successMessageKey = 'successMessage';
  static const defaultSuccessMessage = 'Copied to clipboard';

  String get content => data![_contentKey] as String;
  String get successMessage => data![_successMessageKey] as String;
}

extension ParseExtension on Map<String, Object?> {
  T checkValid<T>(String key) {
    final element = this[key];
    if (element == null) {
      throw FormatException("Missing key '$key'");
    }
    if (element is! T) {
      throw FormatException(
        'Expected element of type $T but got element of type '
        '${element.runtimeType}.',
      );
    }
    return element as T;
  }
}
