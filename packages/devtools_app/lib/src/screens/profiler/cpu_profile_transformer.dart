// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:math' as math;

import '../../shared/constants.dart';
import '../../shared/primitives/utils.dart';
import 'cpu_profile_model.dart';

/// Process for composing [CpuProfileData] into a structured tree of
/// [CpuStackFrame]'s.
class CpuProfileTransformer {
  /// Number of stack frames we will process in each batch.
  static const _defaultBatchSize = 100;

  int _stackFramesProcessed = 0;

  String? _activeProcessId;

  Future<void> processData(
    CpuProfileData cpuProfileData, {
    required String processId,
  }) async {
    // Do not process this data if it has already been processed.
    if (cpuProfileData.processed) return;

    // Reset the transformer before processing.
    reset();

    _activeProcessId = processId;
    final stackFramesCount = cpuProfileData.stackFrames.length;
    final stackFrameValues = cpuProfileData.stackFrames.values.iterator;

    // At minimum, process the data in 4 batches to smooth the appearance of
    // the progress indicator.
    final quarterBatchSize = (stackFramesCount / 4).round();
    var batchSize = math.min(
      _defaultBatchSize,
      quarterBatchSize == 0 ? 1 : quarterBatchSize,
    );
    // Use batch processing to maintain a responsive UI.
    while (_stackFramesProcessed < stackFramesCount) {
      final watch = Stopwatch()..start();
      _processBatch(
        batchSize,
        cpuProfileData,
        processId: processId,
        stackFrameValues: stackFrameValues,
      );
      watch.stop();
      // Avoid divide by zero
      final elapsedMs = math.max(watch.elapsedMilliseconds, 1);
      // Adjust to use half the frame budget.
      batchSize = math.max(
        (batchSize * frameBudgetMs * 0.5 / elapsedMs).ceil(),
        1,
      );

      // Await a small delay to give the UI thread a chance to update the
      // progress indicator. Use a longer delay than the default (0) so that the
      // progress indicator will look smoother.
      await delayToReleaseUiThread(micros: 5000);

      if (processId != _activeProcessId) {
        throw ProcessCancelledException();
      }
    }

    if (cpuProfileData.rootedAtTags) {
      // Check to see if there are any empty tag roots as a result of filtering
      // and remove them.
      final nodeIndicesToRemove = <int>[];
      for (
        int i = cpuProfileData.cpuProfileRoot.children.length - 1;
        i >= 0;
        --i
      ) {
        final root = cpuProfileData.cpuProfileRoot.children[i];
        if (root.isTag && root.children.isEmpty) {
          nodeIndicesToRemove.add(i);
        }
      }
      // TODO(jakemac53): This is O(N^2), we should have a function to remove
      // multiple children at once.
      nodeIndicesToRemove.forEach(
        cpuProfileData.cpuProfileRoot.removeChildAtIndex,
      );
    }

    _setExclusiveSampleCountsAndTags(cpuProfileData);
    cpuProfileData.processed = true;

    assert(
      cpuProfileData.profileMetaData.sampleCount ==
          cpuProfileData.cpuProfileRoot.inclusiveSampleCount,
      'SampleCount from response (${cpuProfileData.profileMetaData.sampleCount})'
      ' != sample count from root '
      '(${cpuProfileData.cpuProfileRoot.inclusiveSampleCount})',
    );

    // We always show the bottom up roots first, so it is fine to eagerly
    // compute.
    await cpuProfileData.computeBottomUpRoots();

    // Reset the transformer after processing.
    reset();
  }

  void _processBatch(
    int batchSize,
    CpuProfileData cpuProfileData, {
    required String processId,
    required Iterator<CpuStackFrame> stackFrameValues,
  }) {
    for (int i = 0; i < batchSize && stackFrameValues.moveNext(); i++) {
      if (processId != _activeProcessId) {
        throw ProcessCancelledException();
      }
      final stackFrame = stackFrameValues.current;
      final parent = cpuProfileData.stackFrames[stackFrame.parentId];
      _processStackFrame(stackFrame, parent, cpuProfileData);
      _stackFramesProcessed++;
    }
  }

  void _processStackFrame(
    CpuStackFrame stackFrame,
    CpuStackFrame? parent,
    CpuProfileData cpuProfileData,
  ) {
    // [stackFrame] is the root of a new cpu sample. Add it as a child of
    // [cpuProfileRoot].
    if (parent == null) {
      cpuProfileData.cpuProfileRoot.addChild(stackFrame);
    } else {
      parent.addChild(stackFrame);
    }
  }

  void _setExclusiveSampleCountsAndTags(CpuProfileData cpuProfileData) {
    for (final sample in cpuProfileData.cpuSamples) {
      final leafId = sample.leafId;
      final stackFrame = cpuProfileData.stackFrames[leafId];
      assert(
        stackFrame != null,
        'No StackFrame found for id $leafId. If you see this assertion, please '
        'export the timeline trace and send to kenzieschmoll@google.com. Note: '
        'you must export the timeline immediately after the AssertionError is '
        'thrown.',
      );
      if (stackFrame != null && !stackFrame.isTag) {
        stackFrame.exclusiveSampleCount++;
      }
    }
  }

  void reset() {
    _activeProcessId = null;
    _stackFramesProcessed = 0;
  }
}

/// Merges CPU profile roots that share a common call stack (starting at the
/// root).
///
/// Ex. C               C                     C
///      -> B             -> B        -->      -> B
///          -> A             -> D                 -> A
///                                                -> D
///
/// At the time this method is called, we assume we have a list of roots with
/// accurate inclusive/exclusive sample counts.
Future<void> mergeCpuProfileRoots(
  List<CpuStackFrame> roots, {
  Stopwatch? stopwatch,
}) async {
  stopwatch ??= Stopwatch()..start();
  if (stopwatch.elapsedMilliseconds > frameBudgetMs * 0.5) {
    await delayToReleaseUiThread(micros: 5000);
    stopwatch.reset();
  }
  final mergedRoots = <CpuStackFrame>[];
  final rootIndicesToRemove = <int>{};

  // The index from which we will traverse to find root matches.
  var traverseIndex = 0;

  for (int i = 0; i < roots.length; i++) {
    if (rootIndicesToRemove.contains(i)) {
      // We have already merged [root]. Do not attempt to merge again.
      continue;
    }

    final root = roots[i];

    // Begin traversing from the index after [i] since we have already seen
    // every node at index <= [i].
    traverseIndex = i + 1;

    for (int j = traverseIndex; j < roots.length; j++) {
      final otherRoot = roots[j];
      final isMatch =
          !rootIndicesToRemove.contains(j) && otherRoot.matches(root);
      if (isMatch) {
        otherRoot.children.forEach(root.addChild);
        root.exclusiveSampleCount += otherRoot.exclusiveSampleCount;
        root.inclusiveSampleCount += otherRoot.inclusiveSampleCount;
        rootIndicesToRemove.add(j);
        await mergeCpuProfileRoots(root.children, stopwatch: stopwatch);
      }
    }
    mergedRoots.add(root);
  }

  // Clearing and adding all the elements in [mergedRoots] is more performant
  // than removing each root that was merged individually.
  roots
    ..clear()
    ..addAll(mergedRoots);
  for (int i = 0; i < roots.length; i++) {
    roots[i].index = i;
  }
}
