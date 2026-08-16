// Copyright 2023-2024 kuloud
//
// Licensed under the Apache License, Version 2.0 (the "License");

part of '../amap_map2.dart';

/// 定位精度模式。
enum AMapLocationAccuracy {
  /// 优先定位精度，耗电量较高。
  high,

  /// 平衡定位精度与耗电量。
  balanced,
}

/// 独立定位参数。
class AMapLocationOptions {
  const AMapLocationOptions({
    this.accuracy = AMapLocationAccuracy.high,
    this.interval = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 10),
  });

  final AMapLocationAccuracy accuracy;

  /// 连续定位的期望回调间隔。Android 端最小为 1 秒。
  final Duration interval;

  /// 单次定位超时时间。
  final Duration timeout;

  Map<String, Object> toMap() => <String, Object>{
        'accuracy': accuracy.name,
        'interval': interval.inMilliseconds,
        'timeout': timeout.inMilliseconds,
      };

  void _validate() {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', '必须大于零。');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', '必须大于零。');
    }
  }
}

/// 高德独立定位客户端。
///
/// 返回坐标按高德坐标语义处理。本客户端不主动申请系统定位权限，调用前请由宿主应用完成授权。
class AMapLocationClient {
  AMapLocationClient._();

  static final AMapLocationClient instance = AMapLocationClient._();

  static const MethodChannel _channel = MethodChannel('amap_map2/location');
  static const EventChannel _eventChannel =
      EventChannel('amap_map2/location_events');

  Stream<AMapLocation>? _locations;

  /// 获取一次当前位置。
  ///
  /// 同一时刻只允许一个单次定位请求。返回结果面向中国境内 GCJ-02 场景。
  Future<AMapLocation> getCurrentLocation({
    AMapLocationOptions options = const AMapLocationOptions(),
  }) async {
    options._validate();
    await _initializeNative();
    final dynamic value = await _channel.invokeMethod<dynamic>(
        'location#getCurrent', options.toMap());
    final AMapLocation? location = AMapLocation.fromMap(value);
    if (location == null) {
      throw PlatformException(
        code: 'location_failed',
        message: '定位 SDK 未返回有效位置。',
      );
    }
    return location;
  }

  /// 开始连续定位。
  ///
  /// 重复调用会用新参数重启连续定位，不会影响正在执行的单次定位。
  Future<void> startLocation({
    AMapLocationOptions options = const AMapLocationOptions(),
  }) async {
    options._validate();
    await _initializeNative();
    await _channel.invokeMethod<void>('location#start', options.toMap());
  }

  /// 连续定位结果流。应先调用 [startLocation]。
  Stream<AMapLocation> get locations => _locations ??= _eventChannel
          .receiveBroadcastStream()
          .map<AMapLocation>((dynamic value) {
        final AMapLocation? location = AMapLocation.fromMap(value);
        if (location == null) {
          throw const FormatException('定位 SDK 返回了无效的位置数据。');
        }
        return location;
      });

  /// 停止连续定位。该方法不会取消单次定位请求。
  Future<void> stopLocation() => _channel.invokeMethod<void>('location#stop');

  static Future<void> _initializeNative() async {
    // 独立服务可能在没有创建 AMapWidget 时使用，因此每次操作前同步初始化配置。
    final AMapPrivacyStatement? privacy = AMapInitializer._privacyStatement;
    if (privacy?.hasContains != true ||
        privacy?.hasShow != true ||
        privacy?.hasAgree != true) {
      throw PlatformException(
        code: 'privacy_not_agreed',
        message: '使用高德定位或地理编码前必须完成隐私合规配置。',
      );
    }
    await _channel.invokeMethod<void>('services#initialize', <String, dynamic>{
      'apiKey': AMapInitializer._apiKey?.toMap(),
      'privacyStatement': privacy!.toMap(),
    });
  }

  static Future<void> _updatePrivacyStatement(
    AMapPrivacyStatement privacyStatement,
  ) =>
      _channel.invokeMethod<void>(
        'services#updatePrivacy',
        privacyStatement.toMap(),
      );
}
