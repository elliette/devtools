// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@TestOn('vm')
import 'dart:convert';
import 'dart:io';

import 'package:devtools_app/src/screens/debugger/span_parser.dart';
import 'package:devtools_app/src/screens/debugger/syntax_highlighter.dart';
import 'package:devtools_app/src/shared/config_specific/ide_theme/ide_theme.dart';
import 'package:devtools_app/src/shared/globals.dart';
import 'package:devtools_app/src/shared/routing.dart';
import 'package:devtools_app/src/shared/theme.dart';
import 'package:devtools_test/devtools_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const modifierSpans = [
  // Start multi-capture spans
  'import "foo";',
  'export "foo";',
  'part of "baz";',
  'part "foo";',
  'export "foo";',
  // End multi-capture spans
  '@annotation',
  'true',
  'false',
  'null',
  'as',
  'abstract',
  'class',
  'enum',
  'extends',
  'extension',
  'external',
  'factory',
  'implements',
  'get',
  'mixin',
  'native',
  'operator',
  'set',
  'typedef',
  'with',
  'covariant',
  'static',
  'final',
  'const',
  'required',
  'late',
];

const controlFlowSpans = [
  'try',
  'on',
  'catch',
  'finally',
  'throw',
  'rethrow',
  'break',
  'case',
  'continue',
  'default',
  'do',
  'else',
  'for',
  'if',
  'in',
  'return',
  'switch',
  'while',
  'sync',
  'async',
  'await',
  'yield',
  'assert',
  'new',
];

const declarationSpans = [
  'this',
  'super',
  'bool',
  'num',
  'int',
  'double',
  'dynamic',
  '_PrivateDeclaration',
  'PublicDeclaration',
];

const functionSpans = [
  'foo()',
  '_foo()',
  'foo(bar)',
];

const numericSpans = [
  '1',
  '1.1',
  '0xFF',
  '0xff',
  '1.3e5',
  '1.3E5',
];

const helloWorld = '''
Future<void> main() async {
  print('hello world!');
}
''';

const multilineDoc = '''
/**
 * Multiline
 */
''';

const docCodeReference = '''
/// This is a code reference for [Foo]
''';

const variableReferenceInString = '''
'\$i: \${foo[i] == bar[i]}'
''';

void main() {
  late Grammar grammar;
  setUp(() async {
    final grammarFile = File('assets/dart_syntax.json');
    expect(grammarFile.existsSync(), true);

    final grammarJson = json.decode(await grammarFile.readAsString());
    grammar = Grammar.fromJson(grammarJson);
    setGlobal(IdeTheme, IdeTheme());
  });

  Color? defaultTextColor(_) => const TextStyle().color;
  Color commentSyntaxColor(ColorScheme scheme) => scheme.commentSyntaxColor;
  Color controlFlowSyntaxColor(ColorScheme scheme) =>
      scheme.controlFlowSyntaxColor;
  Color declarationSyntaxColor(ColorScheme scheme) =>
      scheme.declarationsSyntaxColor;
  Color functionSyntaxColor(ColorScheme scheme) => scheme.functionSyntaxColor;
  Color modifierSyntaxColor(ColorScheme scheme) => scheme.modifierSyntaxColor;
  Color numericConstantSyntaxColor(ColorScheme scheme) =>
      scheme.numericConstantSyntaxColor;
  Color stringSyntaxColor(ColorScheme scheme) => scheme.stringSyntaxColor;
  Color variableSyntaxColor(ColorScheme scheme) => scheme.variableSyntaxColor;

  void spanTester(
    BuildContext context,
    TextSpan span,
    String expectedText,
    Color? Function(ColorScheme) expectedColor,
  ) {
    expect(span.text, expectedText);
    expect(
      span.style,
      TextStyle(
        color: expectedColor(Theme.of(context).colorScheme),
      ),
    );
  }

  void runTestsWithTheme({required bool useDarkTheme}) {
    group(
      'Syntax Highlighting (${useDarkTheme ? 'Dark' : 'Light'} Theme)',
      () {
        Widget buildSyntaxHighlightingTestContext(
          Function(BuildContext) callback,
        ) {
          return MaterialApp.router(
            theme: themeFor(
              isDarkTheme: useDarkTheme,
              ideTheme: getIdeTheme(),
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: useDarkTheme ? darkColorScheme : lightColorScheme,
              ),
            ),
            routerDelegate: DevToolsRouterDelegate(
              (a, b, c, d) => const CupertinoPage(child: SizedBox.shrink()),
            ),
            routeInformationParser: DevToolsRouteInformationParser(),
            builder: (context, _) {
              callback(context);
              return Container();
            },
          );
        }

        testWidgetsWithContext(
          'hello world smoke',
          (WidgetTester tester) async {
            final highlighter = SyntaxHighlighter.withGrammar(
              grammar: grammar,
              source: helloWorld,
            );

            await tester.pumpWidget(
              buildSyntaxHighlightingTestContext(
                (context) {
                  final highlightedLines = highlighter.highlight(context);
                  // final children = highlighted.children!;

                  spanTester(
                    context,
                    highlightedLines[0],
                    'Future',
                    declarationSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[1],
                    '<',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[2],
                    'void',
                    modifierSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[3],
                    '>',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[4] ,
                    ' ',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[5] ,
                    'main',
                    functionSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[6] ,
                    '() ',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[7] ,
                    'async',
                    controlFlowSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[8] ,
                    ' {',
                    defaultTextColor,
                  );

                  expect(highlightedLines[9].toPlainText(), '\n');

                  spanTester(
                    context,
                    highlightedLines[10] ,
                    '  ',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[11] ,
                    'print',
                    functionSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[12] ,
                    '(',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[13] ,
                    "'hello world!'",
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[14] ,
                    ')',
                    defaultTextColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[15] ,
                    ';',
                    defaultTextColor,
                  );

                  expect(highlightedLines[16].toPlainText(), '\n');

                  spanTester(
                    context,
                    highlightedLines[17] ,
                    '}',
                    defaultTextColor,
                  );

                  expect(highlightedLines[18].toPlainText(), '\n');

                  return Container();
                },
              ),
            );
          },
        );

        testWidgetsWithContext(
          'multiline documentation',
          (WidgetTester tester) async {
            final highlighter = SyntaxHighlighter.withGrammar(
              grammar: grammar,
              source: multilineDoc,
            );

            await tester.pumpWidget(
              buildSyntaxHighlightingTestContext(
                (context) {
                  final highlightedLines = highlighter.highlight(context);

                  spanTester(
                    context,
                    highlightedLines[0] ,
                    '/**',
                    commentSyntaxColor,
                  );

                  expect(highlightedLines[1].toPlainText(), '\n');

                  spanTester(
                    context,
                    highlightedLines[2] ,
                    ' * Multiline',
                    commentSyntaxColor,
                  );

                  expect(
                    highlightedLines[3].toPlainText(),
                    '\n',
                  );

                  spanTester(
                    context,
                    highlightedLines[4] ,
                    ' */',
                    commentSyntaxColor,
                  );
                },
              ),
            );
          },
        );

        testWidgetsWithContext(
          'documentation code reference',
          (WidgetTester tester) async {
            final highlighter = SyntaxHighlighter.withGrammar(
              grammar: grammar,
              source: docCodeReference,
            );

            await tester.pumpWidget(
              buildSyntaxHighlightingTestContext(
                (context) {
                  final highlightedLines = highlighter.highlight(context);

                  spanTester(
                    context,
                    highlightedLines[0] ,
                    '/// This is a code reference for ',
                    commentSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[1] ,
                    '[Foo]',
                    variableSyntaxColor,
                  );

                  expect(highlightedLines[2].toPlainText(), '\n');
                },
              ),
            );
          },
        );

        testWidgetsWithContext(
          'variable reference in string',
          (WidgetTester tester) async {
            final highlighter = SyntaxHighlighter.withGrammar(
              grammar: grammar,
              source: variableReferenceInString,
            );

            await tester.pumpWidget(
              buildSyntaxHighlightingTestContext(
                (context) {
                  final highlightedLines = highlighter.highlight(context);

                  var i = 0;

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    "'\$",
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    'i',
                    variableSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    ': ',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    '\${',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    'foo',
                    variableSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    '[',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    'i',
                    variableSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    '] == ',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    'bar',
                    variableSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    '[',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    'i',
                    variableSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    ']}',
                    stringSyntaxColor,
                  );

                  spanTester(
                    context,
                    highlightedLines[i++] ,
                    '\'',
                    stringSyntaxColor,
                  );
                },
              ),
            );
          },
        );

        void testSingleSpan(
          String name,
          String spanText,
          Color Function(ColorScheme) colorCallback,
        ) {
          testWidgetsWithContext(
            "$name '$spanText'",
            (WidgetTester tester) async {
              final highlighter = SyntaxHighlighter.withGrammar(
                grammar: grammar,
                source: spanText,
              );

              await tester.pumpWidget(
                buildSyntaxHighlightingTestContext(
                  (context) {
                    final highlightedLines = highlighter.highlight(context);
                    expect(
                      highlightedLines.first.style,
                      TextStyle(
                        color: colorCallback(Theme.of(context).colorScheme),
                      ),
                    );
                    return Container();
                  },
                ),
              );
            },
          );
        }

        group(
          'single span highlighting:',
          () {
            for (final spanText in modifierSpans) {
              testSingleSpan(
                'modifier',
                spanText,
                modifierSyntaxColor,
              );
            }

            for (final spanText in controlFlowSpans) {
              testSingleSpan(
                'control flow',
                spanText,
                controlFlowSyntaxColor,
              );
            }

            for (final spanText in declarationSpans) {
              testSingleSpan(
                'declaration',
                spanText,
                declarationSyntaxColor,
              );
            }

            for (final spanText in functionSpans) {
              testSingleSpan(
                'function',
                spanText,
                functionSyntaxColor,
              );
            }

            for (final spanText in numericSpans) {
              testSingleSpan(
                'numeric',
                spanText,
                numericConstantSyntaxColor,
              );
            }
          },
        );
      },
    );
  }

  runTestsWithTheme(useDarkTheme: false);
  runTestsWithTheme(useDarkTheme: true);
}
