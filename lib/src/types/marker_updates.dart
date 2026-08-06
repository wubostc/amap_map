import 'package:flutter/foundation.dart' show setEquals;

import 'types.dart';

/// 用以描述Marker的更新项
class MarkerUpdates {
  /// 想要添加的marker集合.
  Set<Marker>? markersToAdd;

  /// 想要删除的marker的id集合
  Set<String>? markerIdsToRemove;

  /// 想要更新的marker集合.
  Set<Marker>? markersToChange;

  /// 根据之前的marker列表[previous]和当前的marker列表[current]创建[MakerUpdates].
  MarkerUpdates.from(Set<Marker> previous, Set<Marker> current) {
    final Map<String, Marker> previousMarkers = keyByMarkerId(previous);
    final Map<String, Marker> currentMarkers = keyByMarkerId(current);

    final Set<String> prevMarkerIds = previousMarkers.keys.toSet();
    final Set<String> currentMarkerIds = currentMarkers.keys.toSet();

    Marker idToCurrentMarker(String id) {
      return currentMarkers[id]!;
    }

    final Set<String> tempMarkerIdsToRemove =
        prevMarkerIds.difference(currentMarkerIds);

    final Set<Marker> tempMarkersToAdd = currentMarkerIds
        .difference(prevMarkerIds)
        .map(idToCurrentMarker)
        .toSet();

    bool hasChanged(Marker current) {
      final Marker? previous = previousMarkers[current.id];
      return current != previous;
    }

    final Set<Marker> tempMarkersToChange = currentMarkerIds
        .intersection(prevMarkerIds)
        .map(idToCurrentMarker)
        .where(hasChanged)
        .toSet();

    markersToAdd = tempMarkersToAdd;
    markerIdsToRemove = tempMarkerIdsToRemove;
    markersToChange = tempMarkersToChange;
  }

  MarkerUpdates.add(Set<Marker> markers) : markersToAdd = markers;

  MarkerUpdates.remove(Set<String> markerIds) : markerIdsToRemove = markerIds;

  MarkerUpdates.change(Set<Marker> markers) : markersToChange = markers;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (markersToAdd != null)
        'markersToAdd': serializeOverlaySet(markersToAdd!),
      if (markersToChange != null)
        'markersToChange': serializeOverlaySet(markersToChange!),
      if (markerIdsToRemove != null)
        'markerIdsToRemove': markerIdsToRemove!.toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    if (other is! MarkerUpdates) return false;
    final MarkerUpdates typedOther = other;
    return setEquals(markersToAdd, typedOther.markersToAdd) &&
        setEquals(markerIdsToRemove, typedOther.markerIdsToRemove) &&
        setEquals(markersToChange, typedOther.markersToChange);
  }

  @override
  int get hashCode => Object.hashAll(
      <Object?>[markersToAdd, markerIdsToRemove, markersToChange]);

  @override
  String toString() {
    return '_MarkerUpdates{markersToAdd: $markersToAdd, '
        'markerIdsToRemove: $markerIdsToRemove, '
        'markersToChange: $markersToChange}';
  }
}
