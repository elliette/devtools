// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:convert';
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../shared/console/eval/inspector_tree_v2.dart';
import '../../../shared/diagnostics/diagnostics_node.dart';
import '../../../shared/diagnostics/primitives/source_location.dart';
import '../../../shared/editor/api_classes.dart';
import '../../../shared/editor/editor_client.dart';
import '../../../shared/framework/screen.dart';
import '../../../shared/globals.dart';
import '../../../shared/managers/error_badge_manager.dart';
import '../../../shared/primitives/diagnostics_text_styles.dart';
import '../../../shared/ui/common_widgets.dart';
import '../inspector_controller.dart';

class FlutterLayoutAgent extends StatefulWidget {
  const FlutterLayoutAgent({
    super.key,
    required this.inspectorController,
    required this.widgetProperties,
  });

  final InspectorController inspectorController;
  final List<RemoteDiagnosticsNode> widgetProperties;

  @override
  State<FlutterLayoutAgent> createState() => _FlutterLayoutAgentState();
}

class _FlutterLayoutAgentState extends State<FlutterLayoutAgent> {
  InspectorTreeNode? get selectedNode =>
      widget.inspectorController.selectedNode.value;

  RemoteDiagnosticsNode? get selectedDiagnostic => selectedNode?.diagnostic;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (selectedDiagnostic == null) {
      return const CenteredMessage(
        message: 'Select a Widget to use AI assistance.',
      );
    }
    final error = errorForSelectedDiagnostic();
    return Column(
      children: [
        Expanded(
          child: GeminiChatWidget(
            error: error,
            hintText: 'Ask a question about this Widget',
            prompt: '',
            onChatResponse: _handleChatResponse,
            onSendMessage: _handleSendMessage,
            onSuggestEdits: _handleSuggestEdits,
            onFixError: () async {
              final context = await _buildErrorContext(error);
              print('pressed! \n $context');
            },
          ),
        ),
      ],
    );
  }

  InspectorSourceLocation? creationLocationForSelectedDiagnostic() {
    return widget.widgetProperties
        .firstWhereOrNull((property) => property.creationLocation != null)
        ?.creationLocation;
  }

  DevToolsError? errorForSelectedDiagnostic() {
    // Check whether the selected node has any errors associated with it.
    final inspectorRef = selectedDiagnostic?.valueRef.id;
    final errors = serviceConnection.errorBadgeManager
        .erroredItemsForPage(ScreenMetaData.inspector.id)
        .value;
    final error = errors[inspectorRef];
    return error;
  }

  Future<String> _selectedWidgetInfo() async {
    final creationLocation = creationLocationForSelectedDiagnostic();
    final creationLocationPath = creationLocation?.path!;

    int? line;
    int? column;
    String? sourceCode;

    if (creationLocationPath != null) {
      line = creationLocation!.getLine();
      column = creationLocation.getColumn();
      final fileResponse = await dtdManager.connection.value?.readFileAsString(
        Uri.parse(creationLocationPath),
      );
      sourceCode = fileResponse?.content;
    }

    return '''Here is the widget information:
    line: $line
    column: $column
    source code: $sourceCode
    widget's diagnostic information: ${selectedDiagnostic!.json}
    widget's name: ${selectedDiagnostic!.description ?? ''}.
    widget's immediate children: ${selectedDiagnostic!.childrenNow.map((diagnostic) => diagnostic.description).toList()}
    widget's parent: ${selectedDiagnostic!.parent?.description}
    ''';
  }

  Future<String> _applyEditContext() async {
    final selectedWidgetInfo = await _selectedWidgetInfo();
    return '''
You are a Dart and Flutter expert. You will be given the source code and line
and column of a widget in a users Flutter app, along with an edit that the user
would like to apply. Please return two strings, the first one being the original
code, and the second one being the edited code that should replace the original
code. Please also return the starting line of code to apply the edit to.

The response should come back as a JSON string in the following format:

{
  "original": "crossAxisAlignment: CrossAxisAlignment.start",
  "edited": "crossAxisAlignment: CrossAxisAlignment.baseline",
  "line": 28

}

Here is the widget information:

$selectedWidgetInfo
''';
  }

  Future<String> _buildWidgetContext() async {
    final selectedWidgetInfo = await _selectedWidgetInfo();
    return '''
You are a Dart and Flutter expert. You will be given the source code and line
and column of a widget in a users Flutter app. Based on the source code for that
widget, please suggest a few edits that could be made to improve the widget.

The response should come back as a JSON string in the following format, where
original is the current code, edited is the replacement code, and line is the
line to start the replacement at:

 {
   "edits": [
     {
       "suggestion": "Wrap in padding",
       "original": "child: Text('hello')",
       "edited": "child: Padding(padding: EdgeInsets.all(8.0), child: Text('hello'))"
       "line" 28,
     }
   ]
 }


Here is the widget information:

$selectedWidgetInfo
''';
  }

  Future<String> _buildErrorContext(DevToolsError? error) async {
    final selectedWidgetInfo = await _selectedWidgetInfo();
    return '''
You are a Dart and Flutter expert. You will be given an error message at a
specific line and column in provided Dart source code. You will also be given
additional context about the Widget that the error is associated with. Use this
information to inform the suggested fix.

Please fix the code and return it in it's entirety. The response should be the 
same program as the input with the error fixed.

The response should come back as raw code and not in a Markdown code block.
Make sure to check for layout overflows in the generated code and fix them
before returning the code.

error message: ${error?.errorMessage}
$selectedWidgetInfo
''';
  }

  Future<String?> _handleSendMessage(String message) async {
    final request = await _buildChatMessage(message);
    return await aiController.sendSamplingRequest(
      messages: [request],
      maxTokens: 250,
    );
  }

  Future<List<_SuggestedEdit>?> _handleSuggestEdits() async {
    final request = await _buildWidgetContext();
    final response = await aiController.sendSamplingRequest(
      messages: [request],
      maxTokens: 250,
    );
    if (response != null && mounted) {
      var responseString = response.trim();
      const jsonMarkdownStart = '```json\n';
      const jsonMarkdownEnd = '```';

      if (responseString.startsWith(jsonMarkdownStart) &&
          responseString.endsWith(jsonMarkdownEnd)) {
        responseString = responseString.substring(
          jsonMarkdownStart.length,
          responseString.length - jsonMarkdownEnd.length,
        );
      }
      final decoded = jsonDecode(responseString) as Map<String, Object?>;
      final edits = (decoded['edits'] as List)
          .map((e) => _SuggestedEdit.fromJson(e as Map<String, Object?>))
          .toList();
      return edits;
    }
    return null;
  }

  Future<String> stringFromStream(Stream<String> stream) async {
    final buffer = StringBuffer();
    await stream.forEach(buffer.write);
    return buffer.toString();
  }

  Future<void> _handleChatResponse(String chatResponse) async {
    var cleanResponse = await stringFromStream(
      cleanCode(Stream.value(chatResponse)),
    );
    const chunkEnd = '$endCodeBlock\n';
    if (cleanResponse.endsWith(chunkEnd)) {
      cleanResponse = cleanResponse.substring(
        0,
        cleanResponse.length - chunkEnd.length,
      );
    }
    final filePath = creationLocationForSelectedDiagnostic()?.path;
    if (filePath != null) {
      await dtdManager.connection.value?.writeFileAsString(
        Uri.parse(filePath),
        cleanResponse,
      );
    }
  }

  static const startCodeBlock = '```dart\n';
  static const endCodeBlock = '```';
  static Stream<String> cleanCode(Stream<String> stream) async* {
    var foundFirstLine = false;
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      // looking for the start of the code block (if there is one)
      if (!foundFirstLine) {
        buffer.write(chunk);
        if (chunk.contains('\n')) {
          foundFirstLine = true;
          final text = buffer.toString().replaceFirst(startCodeBlock, '');
          buffer.clear();
          if (text.isNotEmpty) yield text;
          continue;
        }

        // still looking for the start of the first line
        continue;
      }

      // looking for the end of the code block (if there is one)
      assert(foundFirstLine);
      String processedChunk;
      if (chunk.endsWith(endCodeBlock)) {
        processedChunk = chunk.substring(0, chunk.length - endCodeBlock.length);
      } else if (chunk.endsWith('$endCodeBlock\n')) {
        processedChunk =
            '${chunk.substring(0, chunk.length - endCodeBlock.length - 1)}\n';
      } else {
        processedChunk = chunk;
      }

      if (processedChunk.isNotEmpty) yield processedChunk;
    }

    // if we're still in the first line, yield it
    if (buffer.isNotEmpty) yield buffer.toString();
  }

  Future<String> _buildChatMessage(String message) async {
    return '$message\n${await _buildContext()}';
  }

  Future<String> _buildContext() async {
    final creationLocation = widget.widgetProperties
        .firstWhereOrNull((property) => property.creationLocation != null)
        ?.creationLocation;
    String? creationLocationDescription;
    String? creationLibraryContent;
    final creationLocationPath = creationLocation?.path!;
    if (creationLocationPath != null) {
      creationLocationDescription =
          'The location in the Flutter project where the Widget was created is '
          '$creationLocationPath at line: ${creationLocation!.getLine()}, '
          'column: ${creationLocation.getColumn()}';
      final fileContent = (await dtdManager.connection.value?.readFileAsString(
        Uri.parse(creationLocationPath),
      ))?.content;
      creationLibraryContent = fileContent != null
          ? 'The content for the library where this widget was created is here:\n $fileContent'
          : '';
    }

    return '''
You are an expert Dart and Flutter developer. You should use the latest Flutter
SDK APIs to ensure you are suggesting valid Dart code.

I am going to give you context about a Flutter widget from the widget tree of
a running Flutter app. Based on that context, please perform the request that
is at the end of this message.

Here is context about the Widget:

The raw JSON of the widget's diagnostic information is here:
${selectedDiagnostic!.json}

The widget's name is: ${selectedDiagnostic!.description ?? ''}.

The widget's immediate children are: ${selectedDiagnostic!.childrenNow.map((diagnostic) => diagnostic.description).toList()}

The widget's parent is: ${selectedDiagnostic!.parent?.description}

${creationLibraryContent ?? ''}

${creationLocationDescription ?? ''}

The properties for the Widget are: ${widget.widgetProperties.map((node) => node.json).toList()}

''';
  }
}

class GeminiChatWidget extends StatefulWidget {
  const GeminiChatWidget({
    super.key,
    required this.error,
    required this.prompt,
    required this.hintText,
    // this.chatController,
    required this.onSuggestEdits,
    required this.onFixError,
    required this.onSendMessage,
    this.onChatResponse,
  });

  final DevToolsError? error;
  final String prompt;
  final String hintText;
  // final GeminiChatWidgetController? chatController;
  final Future<List<_SuggestedEdit>?> Function() onSuggestEdits;
  final void Function() onFixError;
  final FutureOr<void> Function(String chatResponse)? onChatResponse;
  final Future<String?> Function(String message) onSendMessage;

  @override
  State<GeminiChatWidget> createState() => _GeminiChatWidgetState();
}

class _GeminiChatWidgetState extends State<GeminiChatWidget>
    with AutoDisposeMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocus = FocusNode(debugLabel: 'TextField');
  bool _loading = false;
  final List<_ChatMessage> _history = [];

  @override
  void initState() {
    super.initState();
    // _listenForIncomingChats();
  }

  @override
  void dispose() {
    // _chatController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GeminiChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // if (widget.chatController != oldWidget.chatController) {
    //   cancelListeners();
    //   _listenForIncomingChats();
    // }
  }

  // void _listenForIncomingChats() {
  //   if (widget.chatController != null) {
  //     autoDisposeStreamSubscription(
  //       widget.chatController!._chats.listen((message) async {
  //         await _sendAndHandleChat(message);
  //       }),
  //     );
  //   }
  // }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async => await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCirc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = widget.error?.errorMessage;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemBuilder: (context, idx) {
                final message = _history[idx];
                return _MessageWidget(message: message);
              },
              itemCount: _history.length,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(noPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DevToolsButton(
                  label: 'Explain this widget',
                  icon: Icons.auto_awesome,
                  elevated: true,
                  onPressed: () async {
                    setState(() {
                      _loading = true;
                    });
                    final suggestions = await widget.onSuggestEdits();
                    if (suggestions != null && mounted) {
                      setState(() {
                        _history.add(_BotMessage(suggestions: suggestions));
                      });
                      _scrollDown();
                    }
                    setState(() {
                      _loading = false;
                    });
                  },
                ),
                DevToolsButton(
                  label: 'Suggest widget edits',
                  icon: Icons.auto_awesome,
                  elevated: true,
                  onPressed: () async {
                    setState(() {
                      _loading = true;
                    });
                    final suggestions = await widget.onSuggestEdits();
                    if (suggestions != null && mounted) {
                      setState(() {
                        _history.add(_BotMessage(suggestions: suggestions));
                      });
                      _scrollDown();
                    }
                    setState(() {
                      _loading = false;
                    });
                  },
                ),
              ],
            ),
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(top: defaultSpacing),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RichText(
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      text: errorMessage ?? 'Widget error',
                      // When the node is selected, the background will be an error
                      // color so don't render the text the same color.
                      style: DiagnosticsTextStyles.error(Theme.of(context).colorScheme),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: defaultSpacing),
                    child: DevToolsButton(
                      label: 'Explain error',
                      icon: Icons.auto_awesome,
                      elevated: true,
                      onPressed: widget.onFixError,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: defaultSpacing),
                    child: DevToolsButton(
                      label: 'Fix error',
                      icon: Icons.auto_awesome,
                      elevated: true,
                      onPressed: widget.onFixError,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsetsGeometry.fromLTRB(
              denseSpacing,
              defaultSpacing,
              denseSpacing,
              noPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    focusNode: _textFieldFocus,
                    decoration: textFieldDecoration(context, widget.hintText),
                    controller: _textController,
                    onSubmitted: _sendChatMessage,
                  ),
                ),
                const SizedBox.square(dimension: 15),
                if (!_loading)
                  IconButton(
                    onPressed: () async {
                      await _sendChatMessage(_textController.text);
                    },
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage(String message) async {
    setState(() {
      _loading = true;
    });

    try {
      setState(() {
        _history.add(_UserMessage(text: message));
      });
      _scrollDown();
      final result = await widget.onSendMessage(message);
      if (result != null && mounted) {
        setState(() {
          _history.add(_ChatMessage(text: result, isFromUser: false));
        });
        _scrollDown();
      }
    } catch (e) {
      _showError(e.toString());
      setState(() {
        _loading = false;
      });
    } finally {
      _textController.clear();
      _scrollDown();
      setState(() {
        _loading = false;
      });
      _textFieldFocus.requestFocus();
    }
  }

  void _showError(String message) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Something went wrong'),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({required this.text, required this.isFromUser});

  final String text;
  final bool isFromUser;
}

class _UserMessage extends _ChatMessage {
  _UserMessage({required super.text}) : super(isFromUser: true);
}

class _BotMessage extends _ChatMessage {
  _BotMessage({super.text = '', this.suggestions}) : super(isFromUser: false);

  final List<_SuggestedEdit>? suggestions;
}

class _SuggestedEdit {
  _SuggestedEdit.fromJson(Map<String, Object?> json)
    : suggestion = json['suggestion'] as String,
      original = json['original'] as String,
      edited = json['edited'] as String;

  final String suggestion;
  final String original;
  final String edited;
}

class _MessageWidget extends StatelessWidget {
  const _MessageWidget({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final botMessage = message is _BotMessage ? message as _BotMessage : null;
    final suggestions = botMessage?.suggestions;

    return Row(
      mainAxisAlignment: message.isFromUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: message.isFromUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.isNotEmpty) MarkdownBody(data: message.text),
                if (suggestions != null)
                  ...suggestions.map(
                    (edit) => Padding(
                      padding: const EdgeInsets.only(top: defaultSpacing),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text(edit.suggestion)),
                          const SizedBox(width: defaultSpacing),
                          DevToolsButton(
                            label: 'Apply edit',
                            onPressed: () {
                              print(edit.edited);
                              // TODO(elliette): Implement apply edit functionality.
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration textFieldDecoration(BuildContext context, String hintText) =>
    InputDecoration(
      contentPadding: const EdgeInsets.all(15),
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary),
      ),
    );
