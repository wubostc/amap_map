// Copyright 2023-2024 kuloud
// Copyright 2020 lbs.amap.com
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,

part of '../amap_map2.dart';

final MethodChannelAMapFlutterMap _methodChannel =
    AMapFlutterPlatform.instance as MethodChannelAMapFlutterMap;

/// 地图通信中心
class AMapController {
  final int mapId;
  final MapState _mapState;

  AMapController._(CameraPosition initCameraPosition, this._mapState,
      {required this.mapId}) {
    _connectStreams(mapId);
  }

  ///根据传入的id初始化[AMapController]
  /// 主要用于在[AMapWidget]初始化时在[AMapWidget.onMapCreated]中初始化controller
  static Future<AMapController> init(
    int id,
    CameraPosition initialCameration,
    MapState mapState,
  ) async {
    await _methodChannel.init(id);
    return AMapController._(
      initialCameration,
      mapState,
      mapId: id,
    );
  }

  ///只用于测试
  ///用于与native的通信
  @visibleForTesting
  MethodChannel get channel {
    return _methodChannel.channel(mapId);
  }

  void _connectStreams(int mapId) {
    _methodChannel.onLocationChanged(mapId: mapId).listen(
        (LocationChangedEvent e) =>
            _mapState.widget.onLocationChanged?.call(e.value));

    _methodChannel.onCameraMove(mapId: mapId).listen((CameraMoveEvent e) {
      _mapState.widget.onCameraMove?.call(e.value);
      if (_mapState.widget.infoWindowAdapter != null) {
        _mapState.updateMarkers();
      }
    });

    _methodChannel.onCameraMoveEnd(mapId: mapId).listen((CameraMoveEndEvent e) {
      _mapState.widget.onCameraMoveEnd?.call(e.value);
    });
    _methodChannel.onMapTap(mapId: mapId).listen((MapTapEvent e) {
      _mapState.onMapTap(e.value);
    });
    _methodChannel.onMapLongPress(mapId: mapId).listen(((MapLongPressEvent e) {
      _mapState.widget.onLongPress?.call(e.value);
    }));

    _methodChannel.onPoiTouched(mapId: mapId).listen(((MapPoiTouchEvent e) {
      _mapState.widget.onPoiTouched?.call(e.value);
    }));

    _methodChannel.onMarkerTap(mapId: mapId).listen((MarkerTapEvent e) {
      _mapState.onMarkerTap(e.value);
    });

    _methodChannel.onMarkerDragEnd(mapId: mapId).listen((MarkerDragEndEvent e) {
      _mapState.onMarkerDragEnd(e.value, e.position);
    });

    _methodChannel.onPolylineTap(mapId: mapId).listen((PolylineTapEvent e) {
      _mapState.onPolylineTap(e.value);
    });
  }

  void dispose() {
    _methodChannel.dispose(id: mapId);
  }

  Future<void> _updateMapOptions(Map<String, dynamic> optionsUpdate) {
    return _methodChannel.updateMapOptions(optionsUpdate, mapId: mapId);
  }

  Future<void> _updateMarkers(MarkerUpdates markerUpdates) {
    return _methodChannel.updateMarkers(markerUpdates, mapId: mapId);
  }

  Future<void> _updatePolylines(PolylineUpdates polylineUpdates) {
    return _methodChannel.updatePolylines(polylineUpdates, mapId: mapId);
  }

  Future<void> _updatePolygons(PolygonUpdates polygonUpdates) {
    return _methodChannel.updatePolygons(polygonUpdates, mapId: mapId);
  }

  ///改变地图视角
  ///
  ///通过[CameraUpdate]对象设置新的中心点、缩放比例、放大缩小、显示区域等内容
  ///
  ///（注意：iOS端设置显示区域时，不支持duration参数，动画时长使用iOS地图默认值350毫秒）
  ///
  ///可选属性[animated]用于控制是否执行动画移动
  ///
  ///可选属性[duration]用于控制执行动画的时长,默认250毫秒,单位:毫秒
  Future<void> moveCamera(CameraUpdate cameraUpdate,
      {bool animated = true, int duration = 250}) {
    return _methodChannel.moveCamera(cameraUpdate,
        mapId: mapId, animated: animated, duration: duration);
  }

  ///地图截屏
  Future<Uint8List?> takeSnapshot() {
    return _methodChannel.takeSnapshot(mapId: mapId);
  }

  /// 清空缓存
  Future<void> clearDisk() {
    return _methodChannel.clearDisk(mapId: mapId);
  }

  /// 经纬度转屏幕坐标 since v1.0.3
  Future<ScreenCoordinate> toScreenCoordinate(LatLng latLng) {
    return _methodChannel.toScreenLocation(latLng, mapId: mapId);
  }

  /// 屏幕坐标转经纬度 From v1.0.3
  Future<LatLng> fromScreenCoordinate(ScreenCoordinate screenCoordinate) {
    return _methodChannel.fromScreenLocation(screenCoordinate, mapId: mapId);
  }

  Future<String> getMapContentApprovalNumber() {
    return _methodChannel.getMapContentApprovalNumber(mapId: mapId);
  }

  Future<String> getSatelliteImageApprovalNumber() {
    return _methodChannel.getSatelliteImageApprovalNumber(mapId: mapId);
  }

  /// 设置地图参数
  Future<void> setMapOptions(AMapOptions optionsUpdate) {
    return _methodChannel.updateMapOptions(optionsUpdate.toMap(), mapId: mapId);
  }

  Future<void> setMarker(Marker marker) {
    if (_mapState.upsertMarker(marker) == null) {
      return _methodChannel.updateMarkers(MarkerUpdates.add(<Marker>{marker}),
          mapId: mapId);
    }
    return _methodChannel.updateMarkers(MarkerUpdates.change(<Marker>{marker}),
        mapId: mapId);
  }

  Future<void> removeMarker(String markerId) {
    if (_mapState.removeMarker(markerId) != null) {
      return _methodChannel.updateMarkers(
          MarkerUpdates.remove(<String>{markerId}),
          mapId: mapId);
    }

    return Future<void>.value();
  }

  Future<void> setPolyline(Polyline polyline) {
    if (_mapState.upsertPolyline(polyline) == null) {
      return _methodChannel.updatePolylines(
          PolylineUpdates.add(<Polyline>{polyline}),
          mapId: mapId);
    }

    return _methodChannel.updatePolylines(
        PolylineUpdates.change(<Polyline>{polyline}),
        mapId: mapId);
  }

  Future<void> removePolyline(String polylineId) {
    if (_mapState.removePolyline(polylineId) != null) {
      return _methodChannel.updatePolylines(
          PolylineUpdates.remove(<String>{polylineId}),
          mapId: mapId);
    }

    return Future<void>.value();
  }

  Future<void> setPolygon(Polygon polygon) {
    if (_mapState.upsertPolygon(polygon) == null) {
      return _methodChannel
          .updatePolygons(PolygonUpdates.add(<Polygon>{polygon}), mapId: mapId);
    }

    return _methodChannel.updatePolygons(
        PolygonUpdates.change(<Polygon>{polygon}),
        mapId: mapId);
  }

  Future<void> removePolygon(String polygonId) {
    if (_mapState.removePolygon(polygonId) != null) {
      return _methodChannel.updatePolygons(
          PolygonUpdates.remove(<String>{polygonId}),
          mapId: mapId);
    }

    return Future<void>.value();
  }
}
