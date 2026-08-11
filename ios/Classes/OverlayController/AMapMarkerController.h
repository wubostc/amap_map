//
//  AMapMarkerController.h
//  amap_map2
//
//  Created by lly on 2020/11/3.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <MAMapKit/MAMapKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AMapMarker;

@interface AMapMarkerController : NSObject

- (instancetype)init:(FlutterMethodChannel*)methodChannel
             mapView:(MAMapView*)mapView
           registrar:(NSObject<FlutterPluginRegistrar>*)registrar;

- (nullable AMapMarker *)markerForId:(NSString *)markerId;

/// 获取 Marker 拖拽中事件的采样频率。
/// @param markerId Marker 在 Dart 侧的唯一标识
/// @return 每秒采样次数，未配置时返回 30
- (NSInteger)draggingEventFrequencyForMarkerId:(NSString *)markerId;

- (void)addMarkers:(NSArray*)markersToAdd;

- (void)changeMarkers:(NSArray*)markersToChange;

- (void)removeMarkerIds:(NSArray*)markerIdsToRemove;

//MARK: Marker的回调

- (BOOL)onMarkerTap:(NSString*)markerId;

/// 向 Dart 发送 Marker 开始拖拽事件。
- (BOOL)onMarker:(NSString *)markerId dragStartPosition:(CLLocationCoordinate2D)position;

/// 向 Dart 发送 Marker 拖拽中事件。
- (BOOL)onMarker:(NSString *)markerId draggingPosition:(CLLocationCoordinate2D)position;

/// 向 Dart 发送 Marker 拖拽结束事件。
- (BOOL)onMarker:(NSString *)markerId dragEndPosition:(CLLocationCoordinate2D)position;

//- (BOOL)onInfoWindowTap:(NSString *)markerId;

@end

NS_ASSUME_NONNULL_END
