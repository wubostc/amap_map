// Copyright 2023-2024 kuloud
//
// Licensed under the Apache License, Version 2.0 (the "License");

part of '../amap_map2.dart';

/// POI 查询方式。
enum AMapPoiSearchMode {
  /// 按关键字和城市查询。
  keyword,

  /// 查询坐标周边的 POI。
  around,
}

/// POI 搜索时需要返回的扩展字段。
///
/// 基础字段始终返回。扩展字段是否实际存在还取决于 POI 类型和高德数据。
enum AMapPoiSearchField { children, business, indoor, navi, photos, all }

/// Android `PoiSearchV2` 的高级结果范围。
enum AMapPoiSearchPremium {
  /// 默认结果。
  defaultResult,

  /// 请求完整 POI 结果。
  entirety,
}

/// 关键字和周边查询共用的 POI 参数。
class AMapPoiSearchOptions {
  const AMapPoiSearchOptions({
    this.types,
    this.city,
    this.cityLimit = false,
    this.page = 1,
    this.pageSize = 20,
    this.distanceSort = true,
    this.showFields = const <AMapPoiSearchField>{},
    this.building,
    this.special = true,
    this.queryLanguage = 'zh-CN',
    this.channel,
    this.premium = AMapPoiSearchPremium.defaultResult,
    this.customParams = const <String, String>{},
  });

  /// 类型名称或类型编码。多个值用 `|` 分隔。
  final String? types;

  /// 城市名称、拼音、citycode 或 adcode。
  final String? city;

  /// 关键字查询是否强制限制在 [city] 内搜索。周边查询会忽略此选项。
  final bool cityLimit;

  /// 页码，从 1 开始，最大 100。
  final int page;

  /// 每页数量。为保证 iOS/Android 一致，范围限制为 1 到 25。
  final int pageSize;

  /// 是否按距离排序。周边查询结果的 [AMapPoiSearchItem.distance] 由原生
  /// 地图 SDK 计算，单位为米。
  final bool distanceSort;

  /// 需要返回的扩展字段。
  final Set<AMapPoiSearchField> showFields;

  /// 建筑物 POI ID。设置后只在该建筑物内搜索。
  ///
  /// Android `PoiSearchV2` 支持此参数；iOS 无后缀 POI 2.0 接口没有对应
  /// 字段，因此在 iOS 上会忽略。
  final String? building;

  /// 是否启用高德对特殊 POI（例如火车站）的人工排序干预。
  ///
  /// Android `PoiSearchV2` 支持此参数；iOS 无后缀 POI 2.0 接口没有对应
  /// 字段，因此在 iOS 上会忽略。
  final bool special;

  /// 查询语言，默认值为 `zh-CN`。
  ///
  /// Android 支持 `zh-CN` 或 `en`；iOS 的无后缀 POI 2.0 接口没有对应
  /// 请求字段，会忽略此参数并使用 SDK 当前语言设置。
  final String? queryLanguage;

  /// Android 搜索渠道标识。iOS 没有对应字段，会被忽略。
  final String? channel;

  /// Android `PoiSearchV2` 的高级结果选项。
  final AMapPoiSearchPremium premium;

  /// 传给原生搜索 SDK 的自定义参数。
  final Map<String, String> customParams;

  int get _showFieldsMask {
    // This is the platform-neutral mask used by the method channel.  iOS
    // exposes the same bit positions; Android PoiSearchV2 shifts them down
    // by one before constructing ShowFields.
    if (showFields.contains(AMapPoiSearchField.all)) {
      return -1;
    }
    int mask = 0;
    for (final AMapPoiSearchField field in showFields) {
      switch (field) {
        case AMapPoiSearchField.children:
          mask |= 1 << 1;
        case AMapPoiSearchField.business:
          mask |= 1 << 2;
        case AMapPoiSearchField.indoor:
          mask |= 1 << 3;
        case AMapPoiSearchField.navi:
          mask |= 1 << 4;
        case AMapPoiSearchField.photos:
          mask |= 1 << 5;
        case AMapPoiSearchField.all:
          break;
      }
    }
    return mask;
  }

  void _validate() {
    if (page < 1 || page > 100) {
      throw ArgumentError.value(page, 'page', '页码必须在 1 到 100 之间。');
    }
    if (pageSize < 1 || pageSize > 25) {
      throw ArgumentError.value(pageSize, 'pageSize', '每页数量必须在 1 到 25 之间。');
    }
    _validateOptionalText(types, 'types');
    _validateOptionalText(city, 'city');
    _validateOptionalText(building, 'building');
    final String? normalizedQueryLanguage = queryLanguage?.trim();
    if (normalizedQueryLanguage != null &&
        normalizedQueryLanguage != 'zh-CN' &&
        normalizedQueryLanguage != 'en') {
      throw ArgumentError.value(
        queryLanguage,
        'queryLanguage',
        '只支持 zh-CN 或 en。',
      );
    }
    for (final MapEntry<String, String> entry in customParams.entries) {
      if (entry.key.trim().isEmpty) {
        throw ArgumentError.value(customParams, 'customParams', '参数名不能为空。');
      }
    }
  }

  static void _validateOptionalText(String? value, String name) {
    if (value != null && value.trim().isEmpty) {
      throw ArgumentError.value(value, name, '不能是空字符串。');
    }
  }

  Map<String, dynamic> _toMap({bool includeCityLimit = true}) =>
      <String, dynamic>{
        'types': _trimmedOrNull(types),
        'city': _trimmedOrNull(city),
        'cityLimit': includeCityLimit && cityLimit,
        'page': page,
        'pageSize': pageSize,
        'distanceSort': distanceSort,
        'showFields': _showFieldsMask,
        'building': _trimmedOrNull(building),
        'special': special,
        'queryLanguage': _trimmedOrNull(queryLanguage),
        'channel': _trimmedOrNull(channel),
        'premium':
            premium == AMapPoiSearchPremium.entirety ? 'entirety' : 'default',
        if (customParams.isNotEmpty) 'customParams': customParams,
      };
}

/// 一次 POI 查询请求。
class AMapPoiSearchRequest {
  const AMapPoiSearchRequest._({
    required this.mode,
    this.keyword,
    this.location,
    this.radius = 3000,
    this.options = const AMapPoiSearchOptions(),
  });

  /// 创建关键字查询。
  const factory AMapPoiSearchRequest.keyword({
    String? keyword,
    LatLng? location,
    AMapPoiSearchOptions options,
  }) = _KeywordPoiSearchRequest;

  /// 创建周边查询。
  const factory AMapPoiSearchRequest.around({
    required LatLng location,
    String? keyword,
    int radius,
    AMapPoiSearchOptions options,
  }) = _AroundPoiSearchRequest;

  final AMapPoiSearchMode mode;
  final String? keyword;
  final LatLng? location;
  final int radius;
  final AMapPoiSearchOptions options;

  void _validate() {
    options._validate();
    final String normalizedKeyword = keyword?.trim() ?? '';
    final String normalizedTypes = options.types?.trim() ?? '';
    if (normalizedKeyword.isEmpty && normalizedTypes.isEmpty) {
      throw ArgumentError.value(
        keyword,
        'keyword',
        'keyword 和 types 至少提供一个。',
      );
    }
    if (mode == AMapPoiSearchMode.keyword &&
        options.cityLimit &&
        _trimmedOrNull(options.city) == null) {
      throw ArgumentError.value(
        options.city,
        'city',
        'cityLimit 为 true 时必须提供 city。',
      );
    }
    if (mode == AMapPoiSearchMode.around) {
      if (location == null) {
        throw ArgumentError.value(location, 'location', '周边查询必须提供中心坐标。');
      }
      if (radius < 1 || radius > 50000) {
        throw ArgumentError.value(radius, 'radius', '查询半径必须在 1 到 50000 米之间。');
      }
    }
  }

  Map<String, dynamic> _toMap() {
    return <String, dynamic>{
      'mode': mode.name,
      if (keyword?.trim().isNotEmpty == true) 'keyword': keyword!.trim(),
      if (location != null) 'location': location!.toJson(),
      if (mode == AMapPoiSearchMode.around) 'radius': radius,
      ...options._toMap(includeCityLimit: mode == AMapPoiSearchMode.keyword),
    };
  }
}

class _KeywordPoiSearchRequest extends AMapPoiSearchRequest {
  const _KeywordPoiSearchRequest({
    super.keyword,
    super.location,
    super.options = const AMapPoiSearchOptions(),
  }) : super._(
          mode: AMapPoiSearchMode.keyword,
        );
}

class _AroundPoiSearchRequest extends AMapPoiSearchRequest {
  const _AroundPoiSearchRequest({
    required super.location,
    super.keyword,
    super.radius = 3000,
    super.options = const AMapPoiSearchOptions(),
  }) : super._(
          mode: AMapPoiSearchMode.around,
        );
}

/// POI 图片。
class AMapPoiPhoto {
  const AMapPoiPhoto({this.title, this.url});

  factory AMapPoiPhoto.fromMap(Map<dynamic, dynamic> map) =>
      AMapPoiPhoto(title: map['title'] as String?, url: map['url'] as String?);

  final String? title;
  final String? url;
}

/// POI 的子 POI。
class AMapPoiSubItem {
  const AMapPoiSubItem({
    required this.id,
    required this.name,
    this.location,
    this.snippet,
    this.typeCode,
  });

  factory AMapPoiSubItem.fromMap(Map<dynamic, dynamic> map) {
    return AMapPoiSubItem(
      id: _asString(map['id']) ?? '',
      name: _asString(map['name']) ?? '',
      location: _latLng(map['location']),
      snippet: _asString(map['snippet']),
      typeCode: _asString(map['typeCode']),
    );
  }

  final String id;
  final String name;
  final LatLng? location;
  final String? snippet;
  final String? typeCode;
}

/// 单个 POI 搜索结果。
///
/// Android `PoiItemV2` 和 iOS `AMapPOI` 暴露的字段并不完全相同。所有
/// 平台差异字段都保持可空：当前原生 SDK 没有提供或本次查询没有请求
/// 的字段为 `null`，图片和子 POI 列表没有数据时为空列表。
class AMapPoiSearchItem {
  const AMapPoiSearchItem({
    required this.id,
    required this.name,
    required this.location,
    this.type,
    this.typeCode,
    this.address,
    this.snippet,
    this.tel,
    this.distance,
    this.province,
    this.city,
    this.district,
    this.adCode,
    this.cityCode,
    this.provinceCode,
    this.businessArea,
    this.rating,
    this.cost,
    this.parkingType,
    this.alias,
    this.naviPoiId,
    this.gridCode,
    this.hasIndoorMap,
    this.enterLocation,
    this.exitLocation,
    this.website,
    this.email,
    this.postcode,
    this.photos = const <AMapPoiPhoto>[],
    this.subPois = const <AMapPoiSubItem>[],
  });

  factory AMapPoiSearchItem.fromMap(Map<dynamic, dynamic> map) {
    final LatLng? location = _latLng(map['location']);
    if (location == null) {
      throw const FormatException('POI 结果缺少坐标。');
    }
    // Older native implementations exposed only one of these aliases. Keep
    // the Dart model stable when a mixed-version host is upgrading.
    final String? address = _asString(map['address']);
    final String? snippet = _asString(map['snippet']) ?? address;
    final List<dynamic> rawPhotos = _asList(map['photos']);
    final List<dynamic> rawSubPois = _asList(map['subPois']);
    return AMapPoiSearchItem(
      id: _asString(map['id']) ?? '',
      name: _asString(map['name']) ?? '',
      location: location,
      type: _asString(map['type']),
      typeCode: _asString(map['typeCode']),
      address: address ?? snippet,
      snippet: snippet,
      tel: _asString(map['tel']),
      // The native map SDK calculates this for around searches. Keyword
      // searches intentionally leave it null, matching the native contract.
      distance: _asDouble(map['distance']),
      province: _asString(map['province']),
      city: _asString(map['city']),
      district: _asString(map['district']),
      adCode: _asString(map['adCode']),
      cityCode: _asString(map['cityCode']),
      provinceCode: _asString(map['provinceCode']),
      businessArea: _asString(map['businessArea']),
      rating: _asString(map['rating']),
      cost: _asString(map['cost']),
      parkingType: _asString(map['parkingType']),
      alias: _asString(map['alias']),
      naviPoiId: _asString(map['naviPoiId']),
      gridCode: _asString(map['gridCode']),
      hasIndoorMap: _asBool(map['hasIndoorMap']),
      enterLocation: _latLng(map['enterLocation']),
      exitLocation: _latLng(map['exitLocation']),
      website: _asString(map['website']),
      email: _asString(map['email']),
      postcode: _asString(map['postcode']),
      photos: rawPhotos
          .whereType<Map<dynamic, dynamic>>()
          .map(AMapPoiPhoto.fromMap)
          .toList(growable: false),
      subPois: rawSubPois
          .whereType<Map<dynamic, dynamic>>()
          .map(AMapPoiSubItem.fromMap)
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final LatLng location;
  final String? type;
  final String? typeCode;
  final String? address;
  final String? snippet;

  /// 商业信息中的电话；某些 Android 结果只有请求商业扩展后才会返回。
  final String? tel;

  /// 周边查询中由原生地图 SDK 计算的中心点直线距离，单位为米。
  /// 关键字查询不会返回此字段。
  final double? distance;
  final String? province;
  final String? city;
  final String? district;
  final String? adCode;
  final String? cityCode;
  final String? provinceCode;

  /// 商业扩展字段，可能因平台、请求的 [AMapPoiSearchField.business] 或
  /// 高德数据是否完整而为空。
  final String? businessArea;
  final String? rating;
  final String? cost;
  final String? parkingType;
  final String? alias;
  final String? naviPoiId;
  final String? gridCode;
  final bool? hasIndoorMap;
  final LatLng? enterLocation;
  final LatLng? exitLocation;

  /// iOS `AMapPOI` 提供的字段。Android `PoiItemV2` 没有对应的公开字段，
  /// 因此 Android 通常返回 `null`。
  final String? website;
  final String? email;
  final String? postcode;
  final List<AMapPoiPhoto> photos;
  final List<AMapPoiSubItem> subPois;
}

/// POI 查询结果。
class AMapPoiSearchResult {
  const AMapPoiSearchResult({
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.pois,
  });

  factory AMapPoiSearchResult.fromMap(Map<dynamic, dynamic> map) {
    final List<dynamic> rawPois = _asList(map['pois']);
    return AMapPoiSearchResult(
      totalCount: _asInt(map['totalCount']) ?? 0,
      page: _asInt(map['page']) ?? 1,
      pageSize: _asInt(map['pageSize']) ?? 20,
      pois: rawPois
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> poi) => AMapPoiSearchItem.fromMap(
              poi,
            ),
          )
          .toList(growable: false),
    );
  }

  /// 满足查询条件的总 POI 数量。
  final int totalCount;

  /// 当前页码。
  final int page;

  /// 当前页大小。
  final int pageSize;

  /// 当前页 POI 列表。
  final List<AMapPoiSearchItem> pois;
}

/// 高德 POI 搜索客户端。
class AMapPoiSearchClient {
  AMapPoiSearchClient._();

  static final AMapPoiSearchClient instance = AMapPoiSearchClient._();
  static const MethodChannel _channel = MethodChannel('amap_map2/poi_search');

  /// 执行一次 POI 查询。
  Future<AMapPoiSearchResult> search(AMapPoiSearchRequest request) async {
    request._validate();
    await AMapLocationClient._initializeNative();
    final Map<dynamic, dynamic>? value =
        await _channel.invokeMapMethod<dynamic, dynamic>(
      'poiSearch#search',
      request._toMap(),
    );
    if (value == null) {
      throw const FormatException('POI 搜索未返回结果。');
    }
    return AMapPoiSearchResult.fromMap(value);
  }

  /// 按关键字或类型搜索。
  Future<AMapPoiSearchResult> searchKeyword({
    String? keyword,
    LatLng? location,
    AMapPoiSearchOptions options = const AMapPoiSearchOptions(),
  }) {
    return search(
      AMapPoiSearchRequest.keyword(
        keyword: keyword,
        location: location,
        options: options,
      ),
    );
  }

  /// 查询坐标周边的 POI。
  Future<AMapPoiSearchResult> searchAround({
    required LatLng location,
    String? keyword,
    int radius = 3000,
    AMapPoiSearchOptions options = const AMapPoiSearchOptions(),
  }) {
    return search(
      AMapPoiSearchRequest.around(
        location: location,
        keyword: keyword,
        radius: radius,
        options: options,
      ),
    );
  }
}

LatLng? _latLng(dynamic value) {
  if (value == null) {
    return null;
  }
  try {
    return LatLng.fromJson(value);
  } on Object {
    return null;
  }
}

List<dynamic> _asList(dynamic value) =>
    value is List ? value : const <dynamic>[];

String? _asString(dynamic value) {
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

String? _trimmedOrNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _asDouble(dynamic value) => value is num ? value.toDouble() : null;

int? _asInt(dynamic value) => value is num ? value.toInt() : null;

bool? _asBool(dynamic value) => value is bool ? value : null;
