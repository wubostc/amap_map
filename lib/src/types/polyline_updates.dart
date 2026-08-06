// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart' show setEquals;

import 'types.dart';

/// 该类主要用以描述[Polyline]的增删改等更新操作
class PolylineUpdates {
  /// 用于添加polyline的集合
  Set<Polyline>? polylinesToAdd;

  /// 需要删除的plyline的id集合
  Set<String>? polylineIdsToRemove;

  /// 用于更新polyline的集合
  Set<Polyline>? polylinesToChange;

  /// 通过polyline的前后更新集合构造一个polylineUpdates
  PolylineUpdates.from(Set<Polyline> previous, Set<Polyline> current) {
    final Map<String, Polyline> previousPolylines = keyByPolylineId(previous);
    final Map<String, Polyline> currentPolylines = keyByPolylineId(current);

    final Set<String> prevPolylineIds = previousPolylines.keys.toSet();
    final Set<String> currentPolylineIds = currentPolylines.keys.toSet();

    Polyline idToCurrentPolyline(String id) {
      return currentPolylines[id]!;
    }

    final Set<String> tempPolylineIdsToRemove =
        prevPolylineIds.difference(currentPolylineIds);

    final Set<Polyline> tempPolylinesToAdd = currentPolylineIds
        .difference(prevPolylineIds)
        .map(idToCurrentPolyline)
        .toSet();

    bool hasChanged(Polyline current) {
      final Polyline previous = previousPolylines[current.id]!;
      return current != previous;
    }

    final Set<Polyline> tempPolylinesToChange = currentPolylineIds
        .intersection(prevPolylineIds)
        .map(idToCurrentPolyline)
        .where(hasChanged)
        .toSet();

    polylinesToAdd = tempPolylinesToAdd;
    polylineIdsToRemove = tempPolylineIdsToRemove;
    polylinesToChange = tempPolylinesToChange;
  }

  PolylineUpdates.add(Set<Polyline> polylines) : polylinesToAdd = polylines;

  PolylineUpdates.remove(Set<String> polylineIds)
      : polylineIdsToRemove = polylineIds;

  PolylineUpdates.change(Set<Polyline> polylines)
      : polylinesToChange = polylines;

  /// 将对象装换为可序列化的对象
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (polylinesToAdd != null)
        'polylinesToAdd': serializeOverlaySet(polylinesToAdd!),
      if (polylinesToChange != null)
        'polylinesToChange': serializeOverlaySet(polylinesToChange!),
      if (polylineIdsToRemove != null)
        'polylineIdsToRemove': polylineIdsToRemove!.toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    if (other is! PolylineUpdates) return false;
    final PolylineUpdates typedOther = other;
    return setEquals(polylinesToAdd, typedOther.polylinesToAdd) &&
        setEquals(polylineIdsToRemove, typedOther.polylineIdsToRemove) &&
        setEquals(polylinesToChange, typedOther.polylinesToChange);
  }

  @override
  int get hashCode => Object.hashAll(
      <Object?>[polylinesToAdd, polylineIdsToRemove, polylinesToChange]);

  @override
  String toString() {
    return '_PolylineUpdates{polylinesToAdd: $polylinesToAdd, '
        'polylineIdsToRemove: $polylineIdsToRemove, '
        'polylinesToChange: $polylinesToChange}';
  }
}
