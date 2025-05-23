// Copyright 2021 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:vm_service/vm_service.dart';

/// Entries for each class's statistics.
class ClassHeapDetailStats {
  ClassHeapDetailStats(
    this.classRef, {
    required int bytes,
    int deltaBytes = 0,
    required int instances,
    int deltaInstances = 0,
    bool traceAllocations = false,
  })  : bytesCurrent = bytes,
        bytesDelta = deltaBytes,
        instancesCurrent = instances,
        instancesDelta = deltaInstances,
        isStacktraced = traceAllocations;

  factory ClassHeapDetailStats.fromJson(Map<String, Object?> json) {
    final {'id': classId, 'name': className} = json['class'] as Map;

    return ClassHeapDetailStats(
      ClassRef(id: classId, name: className),
      bytes: json['bytesCurrent'] as int,
      deltaBytes: json['bytesDelta'] as int,
      instances: json['instancesCurrent'] as int,
      deltaInstances: json['instancesDelta'] as int,
      traceAllocations: json['isStackedTraced'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'class': {
          'id': classRef.id,
          'name': classRef.name,
        },
        'bytesCurrent': bytesCurrent,
        'bytesDelta': bytesDelta,
        'instancesCurrent': instancesCurrent,
        'instancesDelta': instancesDelta,
        'isStackedTraced': isStacktraced,
      };

  /// Version of [ClassHeapDetailStats] payload.
  static const version = 1;

  final ClassRef classRef;

  final int instancesCurrent;

  int instancesDelta;

  final int bytesCurrent;

  int bytesDelta;

  bool isStacktraced;

  @override
  String toString() => '[ClassHeapDetailStats class: ${classRef.name}, '
      'count: $instancesCurrent, bytes: $bytesCurrent]';
}
