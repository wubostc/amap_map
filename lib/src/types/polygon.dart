// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Color;
import 'package:x_amap_base/x_amap_base.dart';
import 'base_overlay.dart';
import 'polyline.dart';

/// 线相关的覆盖物类，内部的属性，描述了覆盖物的纹理、颜色、线宽等特征
class Polygon extends BaseOverlay {
  /// 覆盖物的坐标点数组,不能为空
  final List<LatLng> points;

  /// 边框宽度,单位为逻辑像素，同Android中的dp，iOS中的point
  final double strokeWidth;

  /// 边框颜色,默认值为(0xCCC4E0F0)
  final Color strokeColor;

  /// 填充颜色,默认值为(0xC4E0F0CC)
  final Color fillColor;

  /// 是否可见
  final bool visible;

  /// 连接点类型,该参数不支持copy时修改，仅能在初始化时设置一次
  final JoinType joinType;

  /// 点击回调（回调参数为id）
  final ArgumentCallback<String>? onTap;

  /// 默认构造函数
  Polygon(
      {required List<LatLng> points,
      this.strokeWidth = 10,
      this.strokeColor = const Color(0xCC00BFFF),
      this.fillColor = const Color(0xC487CEFA),
      this.visible = true,
      this.joinType = JoinType.bevel,
      this.onTap})
      : assert(points.isNotEmpty),
        points = List<LatLng>.of(points),
        super();

  /// 实际copy函数
  Polygon copyWith({
    List<LatLng>? points,
    double? strokeWidth,
    Color? strokeColor,
    Color? fillColor,
    bool? visible,
    ArgumentCallback<String>? onTap,
  }) {
    Polygon copyPolyline = Polygon(
      points: List<LatLng>.of(points ?? this.points),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeColor: strokeColor ?? this.strokeColor,
      fillColor: fillColor ?? this.fillColor,
      visible: visible ?? this.visible,
      joinType: joinType,
      onTap: onTap ?? this.onTap,
    );
    copyPolyline.setIdForCopy(id);
    return copyPolyline;
  }

  @override
  Polygon clone() => copyWith();

  /// 转换成可以序列化的map
  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'points': _pointsToJson(),
      'strokeWidth': strokeWidth,
      'strokeColor': strokeColor.toARGB32(),
      'fillColor': fillColor.toARGB32(),
      'visible': visible,
      'joinType': joinType.index,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    if (other is! Polygon) return false;
    final Polygon typedOther = other;
    return id == typedOther.id &&
        listEquals(points, typedOther.points) &&
        strokeWidth == typedOther.strokeWidth &&
        strokeColor == typedOther.strokeColor &&
        fillColor == typedOther.fillColor &&
        visible == typedOther.visible &&
        joinType == typedOther.joinType;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        points,
        strokeWidth,
        strokeColor,
        fillColor,
        visible,
        joinType
      ]);

  dynamic _pointsToJson() {
    final List<dynamic> result = <dynamic>[];
    for (final LatLng point in points) {
      result.add(point.toJson());
    }
    return result;
  }
}

Map<String, Polygon> keyByPolygonId(Iterable<Polygon> polylines) {
  // ignore: unnecessary_null_comparison
  if (polylines == null) {
    return <String, Polygon>{};
  }
  return Map<String, Polygon>.fromEntries(polylines.map((Polygon polyline) =>
      MapEntry<String, Polygon>(polyline.id, polyline.clone())));
}
