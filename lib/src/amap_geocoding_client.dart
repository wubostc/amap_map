// Copyright 2023-2024 kuloud
//
// Licensed under the Apache License, Version 2.0 (the "License");

part of '../amap_map2.dart';

/// 正向地理编码结果。
class AMapGeocodeResult {
  const AMapGeocodeResult({
    required this.location,
    required this.formattedAddress,
    this.country,
    this.province,
    this.city,
    this.district,
    this.township,
    this.neighborhood,
    this.building,
    this.adCode,
    this.cityCode,
    this.level,
  });

  factory AMapGeocodeResult.fromMap(Map<dynamic, dynamic> map) {
    final LatLng? location = LatLng.fromJson(map['location']);
    if (location == null) {
      throw const FormatException('地理编码结果缺少坐标。');
    }
    return AMapGeocodeResult(
      location: location,
      formattedAddress: map['formattedAddress'] as String? ?? '',
      country: map['country'] as String?,
      province: map['province'] as String?,
      city: map['city'] as String?,
      district: map['district'] as String?,
      township: map['township'] as String?,
      neighborhood: map['neighborhood'] as String?,
      building: map['building'] as String?,
      adCode: map['adCode'] as String?,
      cityCode: map['cityCode'] as String?,
      level: map['level'] as String?,
    );
  }

  /// 高德坐标。
  final LatLng location;

  /// SDK 返回的完整格式化地址。
  final String formattedAddress;

  /// 国家。
  final String? country;

  /// 省或直辖市。
  final String? province;

  /// 城市。
  final String? city;

  /// 区县。
  final String? district;

  /// 乡镇或街道。
  final String? township;

  /// 社区。
  final String? neighborhood;

  /// 建筑物。
  final String? building;

  /// 行政区划代码。
  final String? adCode;

  /// 城市代码。
  final String? cityCode;

  /// 地址匹配等级。
  final String? level;
}

/// 逆地理编码结果。
class AMapReverseGeocodeResult {
  const AMapReverseGeocodeResult({
    required this.location,
    required this.formattedAddress,
    this.placeName,
    this.country,
    this.province,
    this.city,
    this.district,
    this.township,
    this.neighborhood,
    this.building,
    this.street,
    this.number,
    this.adCode,
    this.cityCode,
    this.townCode,
  });

  factory AMapReverseGeocodeResult.fromMap(Map<dynamic, dynamic> map) {
    final LatLng? location = LatLng.fromJson(map['location']);
    if (location == null) {
      throw const FormatException('逆地理编码结果缺少坐标。');
    }
    return AMapReverseGeocodeResult(
      location: location,
      formattedAddress: map['formattedAddress'] as String? ?? '',
      placeName: map['placeName'] as String?,
      country: map['country'] as String?,
      province: map['province'] as String?,
      city: map['city'] as String?,
      district: map['district'] as String?,
      township: map['township'] as String?,
      neighborhood: map['neighborhood'] as String?,
      building: map['building'] as String?,
      street: map['street'] as String?,
      number: map['number'] as String?,
      adCode: map['adCode'] as String?,
      cityCode: map['cityCode'] as String?,
      townCode: map['townCode'] as String?,
    );
  }

  /// 用户查询的高德坐标。
  final LatLng location;

  /// SDK 返回的完整格式化地址。
  final String formattedAddress;

  /// 查询点附近距离最近的 POI 名称。
  final String? placeName;

  final String? country;
  final String? province;
  final String? city;
  final String? district;
  final String? township;
  final String? neighborhood;
  final String? building;
  final String? street;
  final String? number;
  final String? adCode;
  final String? cityCode;
  final String? townCode;

  /// 适合直接显示在选点界面的地点名。
  ///
  /// 当附近没有 POI 时，依次退化为建筑、社区、街道和完整地址。
  String get displayName {
    for (final String? value in <String?>[
      placeName,
      building,
      neighborhood,
      street,
      formattedAddress,
    ]) {
      if (value?.trim().isNotEmpty == true) {
        return value!.trim();
      }
    }
    return '';
  }
}

/// 高德地理编码客户端（地址与坐标互转）。
class AMapGeocodingClient {
  AMapGeocodingClient._();

  static final AMapGeocodingClient instance = AMapGeocodingClient._();
  static const MethodChannel _channel = MethodChannel('amap_map2/geocoding');

  /// 将地址转换为高德坐标。
  ///
  /// [city] 可传城市名、城市编码或行政区划代码以缩小搜索范围。
  /// 地址可能匹配多个结果，因此返回列表；无匹配时返回空列表。
  Future<List<AMapGeocodeResult>> geocode({
    required String address,
    String? city,
  }) async {
    final String normalizedAddress = address.trim();
    if (normalizedAddress.isEmpty) {
      throw ArgumentError.value(address, 'address', '地址不能为空。');
    }
    await AMapLocationClient._initializeNative();
    final List<dynamic>? values = await _channel.invokeListMethod<dynamic>(
      'geocoding#geocode',
      <String, dynamic>{
        'address': normalizedAddress,
        if (city?.trim().isNotEmpty == true) 'city': city!.trim(),
      },
    );
    return (values ?? const <dynamic>[])
        .map<AMapGeocodeResult>((dynamic value) =>
            AMapGeocodeResult.fromMap(value as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  /// 查询高德坐标附近的地点名和地址。
  ///
  /// [radius] 单位为米，范围为 0 到 3000；此接口不需要系统定位权限。
  Future<AMapReverseGeocodeResult> reverseGeocode({
    required LatLng location,
    int radius = 1000,
  }) async {
    if (radius < 0 || radius > 3000) {
      throw ArgumentError.value(radius, 'radius', '查询半径必须在 0 到 3000 米之间。');
    }
    await AMapLocationClient._initializeNative();
    final Map<dynamic, dynamic>? value =
        await _channel.invokeMapMethod<dynamic, dynamic>(
      'geocoding#reverseGeocode',
      <String, dynamic>{
        'location': location.toJson(),
        'radius': radius,
      },
    );
    if (value == null) {
      throw const FormatException('逆地理编码未返回结果。');
    }
    return AMapReverseGeocodeResult.fromMap(value);
  }
}
