import 'package:amap_map/src/types/polygon.dart';
import 'package:turf/turf.dart' as turf;
import 'package:x_amap_base/x_amap_base.dart';

/// Returns the topmost tappable polygon that contains [position].
Polygon? hitTestPolygonTapTarget(
  Iterable<Polygon> polygons,
  LatLng position,
) {
  final List<Polygon> polygonList = polygons.toList(growable: false);
  for (final Polygon polygon in polygonList.reversed) {
    if (!polygon.visible || polygon.onTap == null) {
      continue;
    }
    if (containsLatLngInPolygon(polygon.points, position)) {
      return polygon;
    }
  }
  return null;
}

/// Tests whether [position] is inside or on the boundary of [points].
bool containsLatLngInPolygon(List<LatLng> points, LatLng position) {
  if (points.length < 3) {
    return false;
  }

  final List<turf.Position> ring = points
      .map((LatLng point) => turf.Position(point.longitude, point.latitude))
      .toList();
  final turf.Position first = ring.first;
  final turf.Position last = ring.last;
  if (first.lng != last.lng || first.lat != last.lat) {
    ring.add(first);
  }

  return turf.booleanPointInPolygon(
    turf.Position(position.longitude, position.latitude),
    turf.Polygon(coordinates: <List<turf.Position>>[ring]),
  );
}
