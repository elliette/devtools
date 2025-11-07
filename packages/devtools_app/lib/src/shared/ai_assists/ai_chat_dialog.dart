// Copyright 2025 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../shared/framework/screen.dart';
import '../../shared/globals.dart';

class AiChatDialog extends StatefulWidget {
  const AiChatDialog({super.key, required this.currentScreen});

  final Screen currentScreen;

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  final _textController = TextEditingController();
  final _messages = <_ChatMessage>[];
  final _scrollController = ScrollController();
  bool _isThinking = false;

  Future<void> _sendMessage() async {
    final text = _textController.text;
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
    });
    _textController.clear();
    setState(() {
      _isThinking = true;
    });
    _scrollToBottom();

    final preamble =
        '''The following message is a question from a user about Flutter
        DevTools. The user is currently on the ${widget.currentScreen.screenId}
        panel in Flutter DevTools and most likely has questions about that panel.
         Please tailor your answer to the Flutter DevTools context.''';

    // Add tooling call.
    // preamble += '''Additionally, please call get_selected_widget to get
    // information about the currently selected widget (including the name) and 
    // specify that in your response.''';

    final response = await aiController.sendSamplingRequest(
      messages: [preamble, text],
      maxTokens: 250,
    );
    setState(() {
      _messages.add(
        _ChatMessage(
          text: response ?? 'Sorry, I encountered an error.',
          isUser: false,
        ),
      );
    });

    setState(() {
      _isThinking = false;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('DevTools AI Assistant'),
      content: SizedBox(
        width: 600,
        height: 800,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _ChatMessageBubble(message: message);
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Ask a question...',
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                _isThinking
                    ? const CircularProgressIndicator()
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: message.isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10.0),
        ),
        padding: const EdgeInsets.all(12.0),
        margin: const EdgeInsets.all(4.0),
        child: message.isUser
            ? Text(message.text)
            : MarkdownBody(data: message.text),
      ),
    );
  }
}
