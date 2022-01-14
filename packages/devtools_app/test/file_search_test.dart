// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app/src/debugger/file_search.dart';
import 'package:devtools_app/src/ui/search.dart';
import 'package:devtools_app/src/utils.dart';
import 'package:devtools_test/mocks.dart';
import 'package:devtools_test/wrappers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  final debuggerController = MockDebuggerController.withDefaults();

  Widget buildFileSearch() {
    return MaterialApp(
      home: Scaffold(
        body: Card(
          child: FileSearchField(
            debuggerController: debuggerController,
          ),
        ),
      ),
    );
  }

  group('File search', () {
    setUp(() async {
      when(debuggerController.sortedScripts)
          .thenReturn(ValueNotifier(mockScriptRefs));
    });

    testWidgetsWithWindowSize(
        'Search returns expected files', const Size(1000.0, 4000.0),
        (WidgetTester tester) async {
      await tester.pumpWidget(buildFileSearch());
      final FileSearchFieldState state =
          tester.state(find.byType(FileSearchField));
      final autoCompleteController = state.autoCompleteController;

      autoCompleteController.search = '';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Show all results (truncated to 10):
            'zoo:animals/cats/meow.dart',
            'zoo:animals/cats/purr.dart',
            'zoo:animals/dogs/bark.dart',
            'zoo:animals/dogs/growl.dart',
            'zoo:animals/insects/caterpillar.dart',
            'zoo:animals/insects/cicada.dart',
            'kitchen:food/catering/party.dart',
            'kitchen:food/carton/milk.dart',
            'kitchen:food/milk/carton.dart',
            'travel:adventure/cave_tours_europe.dart',
          ],
        ),
      );
      expect(
          getAutoCompleteSegmentValues(
            autoCompleteController.searchAutoComplete.value,
          ),
          equals(
            ['[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]'],
          ));

      autoCompleteController.search = 'c';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact file name matches:
            'zoo:animals/insects/caterpillar.dart',
            'zoo:animals/insects/cicada.dart',
            'kitchen:food/milk/carton.dart',
            'travel:adventure/cave_tours_europe.dart',
            // Exact full path matches:
            'zoo:animals/cats/meow.dart',
            'zoo:animals/cats/purr.dart',
            'kitchen:food/catering/party.dart',
            'kitchen:food/carton/milk.dart',
            'travel:canada/banff.dart'
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact file name matches:
            '[20-21]',
            '[20-21]',
            '[18-19]',
            '[17-18]',
            // Exact full path matches:
            '[12-13]',
            '[12-13]',
            '[3-4]',
            '[3-4]',
            '[7-8]',
          ],
        ),
      );

      autoCompleteController.search = 'ca';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact file name matches:
            'zoo:animals/insects/caterpillar.dart',
            'zoo:animals/insects/cicada.dart',
            'kitchen:food/milk/carton.dart',
            'travel:adventure/cave_tours_europe.dart',
            // Exact full path matches:
            'zoo:animals/cats/meow.dart',
            'zoo:animals/cats/purr.dart',
            'kitchen:food/catering/party.dart',
            'kitchen:food/carton/milk.dart',
            'travel:canada/banff.dart'
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact file name matches:
            '[20-22]',
            '[22-24]',
            '[18-20]',
            '[17-19]',
            // Exact full path matches:
            '[12-14]',
            '[12-14]',
            '[13-15]',
            '[13-15]',
            '[7-9]'
          ],
        ),
      );

      autoCompleteController.search = 'cat';
      expect(
        getAutoCompleteMatch(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            'zoo:animals/insects/CATerpillar.dart',
            'zoo:animals/CATs/meow.dart',
            'zoo:animals/CATs/purr.dart',
            'kitchen:food/CATering/party.dart',
            'zoo:animals/insects/CicAda.darT',
            'kitchen:food/milk/CArTon.dart',
            'travel:adventure/CAve_Tours_europe.dart'
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact file name matches:
            '[20-23]',
            // Exact full path matches:
            '[12-15]',
            '[12-15]',
            '[13-16]',
            // Fuzzy matches:
            '[20-21, 23-24, 30-31]',
            '[18-19, 19-20, 21-22]',
            '[17-18, 18-19, 22-23]',
          ],
        ),
      );

      /*

      autoCompleteController.search = 'cate';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            'zoo:animals/insects/caterpillar.dart',
            'kitchen:food/catering/party.dart',
            // Fuzzy matches:
            'travel:adventure/cave_tours_europe.dart',
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            '[20-24]',
            '[13-17]',
            // Fuzzy matches:
            '[17-18, 18-19, 22-23, 28-29]'
          ],
        ),
      );

      autoCompleteController.search = 'cater';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            'zoo:animals/insects/caterpillar.dart',
            'kitchen:food/catering/party.dart',
            // Fuzzy matches:
            'travel:adventure/cave_tours_europe.dart',
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            '[20-25]',
            '[13-18]',
            // Fuzzy matches:
            '[17-18, 18-19, 22-23, 28-29, 30-31]'
          ],
        ),
      );

      autoCompleteController.search = 'caterp';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            'zoo:animals/insects/caterpillar.dart',
            // Fuzzy matches:
            'travel:adventure/cave_tours_europe.dart',
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            '[20-26]',
            // Fuzzy matches:
            '[17-18, 18-19, 22-23, 28-29, 30-31, 32-33]'
          ],
        ),
      );

      autoCompleteController.search = 'caterpi';
      expect(
        getAutoCompleteTextValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            'zoo:animals/insects/caterpillar.dart',
          ],
        ),
      );
      expect(
        getAutoCompleteSegmentValues(
          autoCompleteController.searchAutoComplete.value,
        ),
        equals(
          [
            // Exact matches:
            '[20-27]',
          ],
        ),
      );

      autoCompleteController.search = 'caterpie';
      expect(autoCompleteController.searchAutoComplete.value, equals([]));
      */
    });
  });
}

List<String> getAutoCompleteMatch(List<AutoCompleteMatch> matches) {
  return matches
      .map(
        (match) => transformAutoCompleteMatch<String>(
          match: match,
          transformMatchedSegment: (segment) => segment.toUpperCase(),
          transformUnmatchedSegment: (segment) => segment.toLowerCase(),
          combineSegments: (segments) => segments.join(''),
        ),
      )
      .toList();

  // final values = <String>[];
  // for (final match in matches) {
  //   final text = match.text;
  //   final matchedSegments = match.matchedSegments;
  //   if (matchedSegments == null || matchedSegments.isEmpty) {
  //     values.add(text);
  //     break;
  //   }
  //   int previousEndIndex = 0;
  //   String modifiedText = '';
  //   for (final segment in matchedSegments) {
  //     if (previousEndIndex < segment.begin) {
  //       // Add uncapitalized segment before the capitalized segment:
  //       final segmentBefore = text.substring(previousEndIndex, segment.begin);
  //       modifiedText += segmentBefore;
  //     }
  //     // Add the capitalized segment:
  //     final capitalizedSegment =
  //         text.substring(segment.begin, segment.end).toUpperCase();
  //     modifiedText += capitalizedSegment;
  //     previousEndIndex = segment.end;
  //   }
  //   if (previousEndIndex < text.length - 1) {
  //     // Add the last uncapitalized segment:
  //     final lastSegment = text.substring(previousEndIndex);
  //     modifiedText += lastSegment;
  //   }
  //   values.add(modifiedText);
  // }
  // return values;
}

List<String> getAutoCompleteTextValues(List<AutoCompleteMatch> matches) {
  return matches.map((match) => match.text).toList();
}

List<String> getAutoCompleteSegmentValues(List<AutoCompleteMatch> matches) {
  return matches
      .map((match) => convertSegmentsToString(match.matchedSegments))
      .toList();
}

String convertSegmentsToString(List<Range> segments) {
  if (segments == null || segments.isEmpty) {
    return '[]';
  }

  final stringSegments =
      segments.map((segment) => '${segment.begin}-${segment.end}');
  return '[${stringSegments.join(', ')}]';
}
