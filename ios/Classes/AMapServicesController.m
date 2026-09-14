#import "AMapServicesController.h"
#import "AMapPrivacyManager.h"

#import <AMapFoundationKit/AMapFoundationKit.h>
#import <AMapLocationKit/AMapLocationKit.h>
#import <AMapSearchKit/AMapSearchKit.h>
#import <MAMapKit/MAGeometry.h>
#import <CoreLocation/CoreLocation.h>

static NSString *const AMapLocationChannelName = @"amap_map2/location";
static NSString *const AMapGeocodingChannelName = @"amap_map2/geocoding";
static NSString *const AMapPoiSearchChannelName = @"amap_map2/poi_search";
static NSString *const AMapLocationEventsChannelName = @"amap_map2/location_events";

static void AMapPut(NSMutableDictionary *map, NSString *key, id value) {
    if (value != nil) {
        map[key] = value;
    }
}

@class AMapServicesController;

// 每个搜索请求使用独立 delegate，避免并发请求的 FlutterResult 相互覆盖。
@interface AMapGeocodeOperation : NSObject <AMapSearchDelegate>
@property(nonatomic, strong) AMapSearchAPI *search;
@property(nonatomic, copy) FlutterResult result;
@property(nonatomic, copy) void (^completion)(AMapGeocodeOperation *operation);
- (instancetype)initWithResult:(FlutterResult)result
                     completion:(void (^)(AMapGeocodeOperation *operation))completion;
- (void)startWithAddress:(NSString *)address city:(nullable NSString *)city;
- (void)startWithLocation:(AMapGeoPoint *)location radius:(NSInteger)radius;
- (void)cancelForPrivacyRevocation;
- (void)cancelWithCode:(NSString *)code message:(NSString *)message;
@end

@interface AMapPoiSearchOperation : NSObject <AMapSearchDelegate>
@property(nonatomic, strong) AMapSearchAPI *search;
@property(nonatomic, strong) id request;
@property(nonatomic, assign) NSInteger showFields;
// Only around searches expose a distance center in the public API.
@property(nonatomic, strong, nullable) AMapGeoPoint *distanceOrigin;
@property(nonatomic, copy) FlutterResult result;
@property(nonatomic, copy) void (^completion)(AMapPoiSearchOperation *operation);
- (instancetype)initWithResult:(FlutterResult)result
                     completion:(void (^)(AMapPoiSearchOperation *operation))completion;
- (void)startWithArguments:(NSDictionary *)arguments;
- (void)cancelForPrivacyRevocation;
- (void)cancelWithCode:(NSString *)code message:(NSString *)message;
- (void)failWithMessage:(NSString *)message details:(id)details;
- (void)failWithCode:(NSString *)code message:(NSString *)message details:(id)details;
@end

@interface AMapServicesController () <AMapLocationManagerDelegate>
@property(nonatomic, strong) FlutterMethodChannel *locationChannel;
@property(nonatomic, strong) FlutterMethodChannel *geocodingChannel;
@property(nonatomic, strong) FlutterMethodChannel *poiSearchChannel;
@property(nonatomic, strong) FlutterEventChannel *locationEventChannel;
@property(nonatomic, copy, nullable) FlutterEventSink eventSink;
// 单次和连续定位隔离，单次请求不会停止正在运行的连续定位。
@property(nonatomic, strong, nullable) AMapLocationManager *continuousManager;
@property(nonatomic, strong, nullable) AMapLocationManager *singleManager;
@property(nonatomic, copy, nullable) FlutterResult singleResult;
@property(nonatomic, assign) NSTimeInterval eventInterval;
@property(nonatomic, assign) NSTimeInterval lastEventTime;
@property(nonatomic, strong) NSMutableSet<AMapGeocodeOperation *> *geocodeOperations;
@property(nonatomic, strong) NSMutableSet<AMapPoiSearchOperation *> *poiSearchOperations;
@end

static NSArray *AMapPoiPointToArray(AMapGeoPoint *point) {
    if (point == nil) {
        return nil;
    }
    return @[@(point.latitude), @(point.longitude)];
}

static NSDictionary *AMapPoiToMap(AMapPOI *poi,
                                  BOOL includeIndoor,
                                  AMapGeoPoint * _Nullable distanceOrigin) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    AMapPut(map, @"id", poi.uid);
    AMapPut(map, @"name", poi.name);
    AMapPut(map, @"type", poi.type);
    AMapPut(map, @"typeCode", poi.typecode);
    AMapPut(map, @"location", AMapPoiPointToArray(poi.location));
    AMapPut(map, @"address", poi.address);
    // Android PoiItemV2 exposes the same text as `snippet`; expose both
    // aliases so callers do not need platform checks.
    AMapPut(map, @"snippet", poi.address);
    AMapPut(map, @"tel", poi.tel);
    AMapPut(map, @"parkingType", poi.parkingType);
    AMapPut(map, @"website", poi.website);
    AMapPut(map, @"email", poi.email);
    AMapPut(map, @"postcode", poi.postcode);
    AMapPut(map, @"province", poi.province);
    AMapPut(map, @"provinceCode", poi.pcode);
    AMapPut(map, @"city", poi.city);
    AMapPut(map, @"cityCode", poi.citycode);
    AMapPut(map, @"district", poi.district);
    AMapPut(map, @"adCode", poi.adcode);
    if (distanceOrigin != nil && poi.location != nil) {
        // Keep the calculation on the native map SDK. AMapPOI.distance is
        // available for around responses, but calculating from both
        // coordinates matches Android, whose PoiItemV2 has no distance field.
        CLLocationCoordinate2D originCoordinate = CLLocationCoordinate2DMake(
            distanceOrigin.latitude, distanceOrigin.longitude);
        CLLocationCoordinate2D poiCoordinate = CLLocationCoordinate2DMake(
            poi.location.latitude, poi.location.longitude);
        CLLocationDistance distance = MAMetersBetweenMapPoints(
            MAMapPointForCoordinate(originCoordinate),
            MAMapPointForCoordinate(poiCoordinate));
        AMapPut(map, @"distance", @(distance));
    }
    AMapPut(map, @"naviPoiId", poi.naviPOIId);
    AMapPut(map, @"gridCode", poi.gridcode);
    AMapPut(map, @"businessArea", poi.businessArea);
    if (includeIndoor) {
        AMapPut(map, @"hasIndoorMap", @(poi.indoorData != nil
                                         ? poi.indoorData.indoorMap != 0
                                         : poi.hasIndoorMap));
    }
    AMapPut(map, @"enterLocation", AMapPoiPointToArray(poi.enterLocation));
    AMapPut(map, @"exitLocation", AMapPoiPointToArray(poi.exitLocation));

    AMapBusinessData *business = poi.businessData;
    if (business != nil) {
        AMapPut(map, @"businessArea", business.businessArea);
        AMapPut(map, @"tel", poi.tel.length > 0 ? poi.tel : business.tel);
        AMapPut(map, @"rating", business.rating);
        AMapPut(map, @"cost", business.cost);
        AMapPut(map, @"parkingType", business.parkingType);
        AMapPut(map, @"alias", business.alias);
    }
    if (poi.extensionInfo != nil) {
        AMapPut(map, @"rating", @(poi.extensionInfo.rating));
        AMapPut(map, @"cost", @(poi.extensionInfo.cost));
    }

    NSMutableArray *photos = [NSMutableArray array];
    for (AMapImage *image in poi.images) {
        if (image == nil) {
            continue;
        }
        NSMutableDictionary *photo = [NSMutableDictionary dictionary];
        AMapPut(photo, @"title", image.title);
        AMapPut(photo, @"url", image.url);
        [photos addObject:photo];
    }
    map[@"photos"] = photos;

    NSMutableArray *subPois = [NSMutableArray array];
    for (AMapSubPOI *subPoi in poi.subPOIs) {
        if (subPoi == nil) {
            continue;
        }
        NSMutableDictionary *value = [NSMutableDictionary dictionary];
        AMapPut(value, @"id", subPoi.uid);
        AMapPut(value, @"name", subPoi.name);
        AMapPut(value, @"snippet", subPoi.address);
        AMapPut(value, @"typeCode", subPoi.typeCode);
        AMapPut(value, @"location", AMapPoiPointToArray(subPoi.location));
        [subPois addObject:value];
    }
    map[@"subPois"] = subPois;
    return map;
}

static NSString *AMapTrimmedString(id value) {
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? nil : trimmed;
}

static AMapPOISearchShowFieldsType AMapPoiShowFieldsTypeFromMask(NSInteger mask) {
    if (mask < 0) {
        return AMapPOISearchShowFieldsTypeAll;
    }
    if (mask == 0) {
        return AMapPOISearchShowFieldsTypeNone;
    }
    return (AMapPOISearchShowFieldsType)mask;
}

@implementation AMapServicesController

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _geocodeOperations = [NSMutableSet set];
        _poiSearchOperations = [NSMutableSet set];
        _locationChannel = [FlutterMethodChannel methodChannelWithName:AMapLocationChannelName
                                                       binaryMessenger:messenger];
        _geocodingChannel = [FlutterMethodChannel methodChannelWithName:AMapGeocodingChannelName
                                                         binaryMessenger:messenger];
        _poiSearchChannel = [FlutterMethodChannel methodChannelWithName:AMapPoiSearchChannelName
                                                           binaryMessenger:messenger];
        _locationEventChannel = [FlutterEventChannel eventChannelWithName:AMapLocationEventsChannelName
                                                           binaryMessenger:messenger];
        __weak typeof(self) weakSelf = self;
        FlutterMethodCallHandler handler = ^(FlutterMethodCall *call, FlutterResult result) {
            [weakSelf handleMethodCall:call result:result];
        };
        [_locationChannel setMethodCallHandler:handler];
        [_geocodingChannel setMethodCallHandler:handler];
        [_poiSearchChannel setMethodCallHandler:handler];
        [_locationEventChannel setStreamHandler:self];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"services#initialize"]) {
        [self initializeServices:call.arguments result:result];
    } else if ([call.method isEqualToString:@"services#updatePrivacy"]) {
        [self updatePrivacy:[self dictionary:call.arguments] result:result];
    } else if ([call.method isEqualToString:@"location#getCurrent"]) {
        [self getCurrentLocation:[self dictionary:call.arguments] result:result];
    } else if ([call.method isEqualToString:@"location#start"]) {
        [self startLocation:[self dictionary:call.arguments] result:result];
    } else if ([call.method isEqualToString:@"location#stop"]) {
        [self stopContinuousLocation];
        result(nil);
    } else if ([call.method isEqualToString:@"geocoding#geocode"]) {
        [self geocode:[self dictionary:call.arguments] result:result];
    } else if ([call.method isEqualToString:@"geocoding#reverseGeocode"]) {
        [self reverseGeocode:[self dictionary:call.arguments] result:result];
    } else if ([call.method isEqualToString:@"poiSearch#search"]) {
        [self poiSearch:[self dictionary:call.arguments] result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)initializeServices:(id)arguments result:(FlutterResult)result {
    NSDictionary *values = [self dictionary:arguments];
    NSDictionary *privacy = [self dictionary:values[@"privacyStatement"]];
    if (![AMapPrivacyManager isPrivacyAllowed:privacy]) {
        result([FlutterError errorWithCode:@"privacy_not_agreed"
                                   message:@"使用高德服务前必须完成隐私合规配置。"
                                   details:nil]);
        return;
    }

    // 隐私状态必须在 AMapLocationManager 和 AMapSearchAPI 实例化之前设置。
    [AMapPrivacyManager updatePrivacyWithStatement:privacy];

    NSDictionary *apiKey = [self dictionary:values[@"apiKey"]];
    NSString *iosKey = [apiKey[@"iosKey"] isKindOfClass:NSString.class] ? apiKey[@"iosKey"] : nil;
    if (iosKey.length > 0) {
        [AMapServices sharedServices].apiKey = iosKey;
    }
    result(nil);
}

- (void)updatePrivacy:(NSDictionary *)privacy result:(FlutterResult)result {
    BOOL allowed = [AMapPrivacyManager isPrivacyAllowed:privacy];
    if (!allowed) {
        [self cancelActiveOperations];
    }
    [AMapPrivacyManager updatePrivacyWithStatement:privacy];
    result(nil);
}

- (void)getCurrentLocation:(NSDictionary *)options result:(FlutterResult)result {
    if (![self hasLocationPermission:result]) {
        return;
    }
    if (self.singleManager != nil) {
        result([FlutterError errorWithCode:@"location_busy"
                                   message:@"已有单次定位请求正在执行。"
                                   details:nil]);
        return;
    }

    AMapLocationManager *manager = [[AMapLocationManager alloc] init];
    [self configureManager:manager options:options];
    manager.locationTimeout = MAX(2, (NSInteger)ceil([options[@"timeout"] doubleValue] / 1000.0));
    self.singleManager = manager;
    self.singleResult = result;
    __weak typeof(self) weakSelf = self;
    // 明确关闭 reGeocode，单次定位只返回坐标和运动信息。
    BOOL started = [manager requestLocationWithReGeocode:NO
                                         completionBlock:^(CLLocation *location,
                                                           AMapLocationReGeocode *regeocode,
                                                           NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || self.singleManager != manager) {
            return;
        }
        self.singleManager = nil;
        FlutterResult pendingResult = self.singleResult;
        self.singleResult = nil;
        if (pendingResult == nil) {
            return;
        }
        if (error != nil || location == nil) {
            NSString *code = error.code == kCLErrorDenied ? @"permission_denied" : @"location_failed";
            pendingResult([FlutterError errorWithCode:code
                                              message:error.localizedDescription ?: @"定位 SDK 未返回位置。"
                                              details:error == nil ? nil : @(error.code)]);
            return;
        }
        pendingResult([self locationToMap:location]);
    }];
    if (!started) {
        self.singleManager = nil;
        self.singleResult = nil;
        result([FlutterError errorWithCode:@"location_failed"
                                   message:@"无法启动单次定位。"
                                   details:nil]);
    }
}

- (void)startLocation:(NSDictionary *)options result:(FlutterResult)result {
    if (![self hasLocationPermission:result]) {
        return;
    }
    [self stopContinuousLocation];
    AMapLocationManager *manager = [[AMapLocationManager alloc] init];
    [self configureManager:manager options:options];
    manager.delegate = self;
    // 连续定位同样不触发逆地理编码。
    manager.locatingWithReGeocode = NO;
    self.eventInterval = MAX(0.001, [options[@"interval"] doubleValue] / 1000.0);
    self.lastEventTime = 0;
    self.continuousManager = manager;
    [manager startUpdatingLocation];
    result(nil);
}

- (void)configureManager:(AMapLocationManager *)manager options:(NSDictionary *)options {
    NSString *accuracy = [options[@"accuracy"] isKindOfClass:NSString.class]
        ? options[@"accuracy"] : @"high";
    if ([accuracy isEqualToString:@"balanced"]) {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    } else {
        manager.desiredAccuracy = kCLLocationAccuracyBest;
    }
    manager.pausesLocationUpdatesAutomatically = NO;
    manager.allowsBackgroundLocationUpdates = NO;
}

- (void)geocode:(NSDictionary *)arguments result:(FlutterResult)result {
    NSString *address = [arguments[@"address"] isKindOfClass:NSString.class]
        ? [arguments[@"address"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    if (address.length == 0) {
        result([FlutterError errorWithCode:@"geocode_invalid_argument"
                                   message:@"地址不能为空。"
                                   details:nil]);
        return;
    }
    NSString *city = [arguments[@"city"] isKindOfClass:NSString.class] ? arguments[@"city"] : nil;
    __weak typeof(self) weakSelf = self;
    AMapGeocodeOperation *operation = [[AMapGeocodeOperation alloc]
        initWithResult:result completion:^(AMapGeocodeOperation *finishedOperation) {
            [weakSelf.geocodeOperations removeObject:finishedOperation];
        }];
    [self.geocodeOperations addObject:operation];
    [operation startWithAddress:address city:city];
}

- (void)reverseGeocode:(NSDictionary *)arguments result:(FlutterResult)result {
    NSArray *location = [arguments[@"location"] isKindOfClass:NSArray.class]
        ? arguments[@"location"] : nil;
    if (location.count < 2 || ![location[0] isKindOfClass:NSNumber.class] ||
        ![location[1] isKindOfClass:NSNumber.class]) {
        result([FlutterError errorWithCode:@"reverse_geocode_invalid_argument"
                                   message:@"坐标格式无效。"
                                   details:nil]);
        return;
    }
    AMapGeoPoint *point = [AMapGeoPoint locationWithLatitude:[location[0] doubleValue]
                                                   longitude:[location[1] doubleValue]];
    NSInteger radius = [arguments[@"radius"] isKindOfClass:NSNumber.class]
        ? [arguments[@"radius"] integerValue] : 1000;
    __weak typeof(self) weakSelf = self;
    AMapGeocodeOperation *operation = [[AMapGeocodeOperation alloc]
        initWithResult:result completion:^(AMapGeocodeOperation *finishedOperation) {
            [weakSelf.geocodeOperations removeObject:finishedOperation];
        }];
    [self.geocodeOperations addObject:operation];
    [operation startWithLocation:point radius:radius];
}

- (void)poiSearch:(NSDictionary *)arguments result:(FlutterResult)result {
    __weak typeof(self) weakSelf = self;
    AMapPoiSearchOperation *operation = [[AMapPoiSearchOperation alloc]
        initWithResult:result completion:^(AMapPoiSearchOperation *finishedOperation) {
            [weakSelf.poiSearchOperations removeObject:finishedOperation];
        }];
    [self.poiSearchOperations addObject:operation];
    [operation startWithArguments:arguments];
}

- (BOOL)hasLocationPermission:(FlutterResult)result {
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = [[CLLocationManager alloc] init].authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    if (status == kCLAuthorizationStatusNotDetermined ||
        status == kCLAuthorizationStatusDenied ||
        status == kCLAuthorizationStatusRestricted) {
        result([FlutterError errorWithCode:@"permission_denied"
                                   message:@"请先授予系统定位权限。"
                                   details:nil]);
        return NO;
    }
    if (![CLLocationManager locationServicesEnabled]) {
        result([FlutterError errorWithCode:@"location_service_disabled"
                                   message:@"系统定位服务未开启。"
                                   details:nil]);
        return NO;
    }
    return YES;
}

- (NSDictionary *)locationToMap:(CLLocation *)location {
    CLLocationDirection bearing = location.course < 0 ? 0 : location.course;
    CLLocationSpeed speed = location.speed < 0 ? 0 : location.speed;
    return @{
        @"provider": @"iOS",
        @"latLng": @[@(location.coordinate.latitude), @(location.coordinate.longitude)],
        @"accuracy": @(location.horizontalAccuracy),
        @"altitude": @(location.altitude),
        @"bearing": @(bearing),
        @"speed": @(speed),
        @"time": @([location.timestamp timeIntervalSince1970] * 1000.0),
    };
}

- (NSDictionary *)dictionary:(id)value {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (void)amapLocationManager:(AMapLocationManager *)manager
          didUpdateLocation:(CLLocation *)location {
    if (manager != self.continuousManager || self.eventSink == nil) {
        return;
    }
    NSTimeInterval now = location.timestamp.timeIntervalSince1970;
    // iOS SDK 没有回调间隔选项，在通道输出层按 Dart interval 节流。
    if (self.lastEventTime > 0 && now - self.lastEventTime < self.eventInterval) {
        return;
    }
    self.lastEventTime = now;
    self.eventSink([self locationToMap:location]);
}

- (void)amapLocationManager:(AMapLocationManager *)manager didFailWithError:(NSError *)error {
    if (manager == self.continuousManager && self.eventSink != nil) {
        NSString *code = error.code == kCLErrorDenied ? @"permission_denied" : @"location_failed";
        self.eventSink([FlutterError errorWithCode:code
                                           message:error.localizedDescription
                                           details:@(error.code)]);
    }
}

- (void)stopContinuousLocation {
    [self.continuousManager stopUpdatingLocation];
    self.continuousManager.delegate = nil;
    self.continuousManager = nil;
    self.lastEventTime = 0;
}

- (void)cancelActiveOperations {
    [self stopContinuousLocation];
    FlutterResult pendingResult = self.singleResult;
    self.singleResult = nil;
    [self.singleManager stopUpdatingLocation];
    self.singleManager = nil;
    if (pendingResult != nil) {
        pendingResult([FlutterError errorWithCode:@"privacy_not_agreed"
                                          message:@"用户已撤回高德隐私授权。"
                                          details:nil]);
    }
    for (AMapGeocodeOperation *operation in self.geocodeOperations.copy) {
        [operation cancelForPrivacyRevocation];
    }
    [self.geocodeOperations removeAllObjects];
    for (AMapPoiSearchOperation *operation in self.poiSearchOperations.copy) {
        [operation cancelForPrivacyRevocation];
    }
    [self.poiSearchOperations removeAllObjects];
}

- (FlutterError *_Nullable)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    self.eventSink = events;
    return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

- (void)dispose {
    [self.locationChannel setMethodCallHandler:nil];
    [self.geocodingChannel setMethodCallHandler:nil];
    [self.poiSearchChannel setMethodCallHandler:nil];
    [self.locationEventChannel setStreamHandler:nil];
    [self stopContinuousLocation];
    FlutterResult pendingSingleResult = self.singleResult;
    self.singleResult = nil;
    [self.singleManager stopUpdatingLocation];
    self.singleManager = nil;
    if (pendingSingleResult != nil) {
        pendingSingleResult([FlutterError errorWithCode:@"plugin_disposed"
                                                message:@"高德服务控制器已销毁。"
                                                details:nil]);
    }
    for (AMapGeocodeOperation *operation in self.geocodeOperations.copy) {
        [operation cancelWithCode:@"plugin_disposed" message:@"高德服务控制器已销毁。"];
    }
    [self.geocodeOperations removeAllObjects];
    for (AMapPoiSearchOperation *operation in self.poiSearchOperations.copy) {
        [operation cancelWithCode:@"plugin_disposed" message:@"高德服务控制器已销毁。"];
    }
    [self.poiSearchOperations removeAllObjects];
    self.eventSink = nil;
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // The controller is published by AMapFlutterMapPlugin so Flutter invokes
    // this hook before the engine's binary messenger is torn down.
    [self dispose];
}

@end

@implementation AMapGeocodeOperation

- (instancetype)initWithResult:(FlutterResult)result
                     completion:(void (^)(AMapGeocodeOperation *operation))completion {
    self = [super init];
    if (self) {
        _result = [result copy];
        _completion = [completion copy];
        _search = [[AMapSearchAPI alloc] init];
        _search.delegate = self;
    }
    return self;
}

- (void)startWithAddress:(NSString *)address city:(NSString *)city {
    AMapGeocodeSearchRequest *request = [[AMapGeocodeSearchRequest alloc] init];
    request.address = address;
    request.city = city;
    [self.search AMapGeocodeSearch:request];
}

- (void)startWithLocation:(AMapGeoPoint *)location radius:(NSInteger)radius {
    AMapReGeocodeSearchRequest *request = [[AMapReGeocodeSearchRequest alloc] init];
    request.location = location;
    request.radius = radius;
    request.requireExtension = YES;
    [self.search AMapReGoecodeSearch:request];
}

- (void)cancelForPrivacyRevocation {
    [self cancelWithCode:@"privacy_not_agreed" message:@"用户已撤回高德隐私授权。"];
}

- (void)cancelWithCode:(NSString *)code message:(NSString *)message {
    FlutterResult pendingResult = self.result;
    self.result = nil;
    self.search.delegate = nil;
    [self.search cancelAllRequests];
    if (pendingResult != nil) {
        pendingResult([FlutterError errorWithCode:code
                                          message:message
                                          details:nil]);
    }
    [self finish];
}

- (void)onGeocodeSearchDone:(AMapGeocodeSearchRequest *)request
                    response:(AMapGeocodeSearchResponse *)response {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:response.geocodes.count];
    for (AMapGeocode *geocode in response.geocodes) {
        if (geocode.location == nil) {
            continue;
        }
        NSMutableDictionary *value = [NSMutableDictionary dictionary];
        value[@"location"] = @[@(geocode.location.latitude), @(geocode.location.longitude)];
        AMapPut(value, @"formattedAddress", geocode.formattedAddress);
        AMapPut(value, @"country", geocode.country);
        AMapPut(value, @"province", geocode.province);
        AMapPut(value, @"city", geocode.city);
        AMapPut(value, @"district", geocode.district);
        AMapPut(value, @"township", geocode.township);
        AMapPut(value, @"neighborhood", geocode.neighborhood);
        AMapPut(value, @"building", geocode.building);
        AMapPut(value, @"adCode", geocode.adcode);
        AMapPut(value, @"cityCode", geocode.citycode);
        AMapPut(value, @"level", geocode.level);
        [values addObject:value];
    }
    self.result(values);
    [self finish];
}

- (void)onReGeocodeSearchDone:(AMapReGeocodeSearchRequest *)request
                       response:(AMapReGeocodeSearchResponse *)response {
    AMapReGeocode *regeocode = response.regeocode;
    if (regeocode == nil || request.location == nil) {
        FlutterResult pendingResult = self.result;
        if (pendingResult != nil) {
            pendingResult([FlutterError errorWithCode:@"reverse_geocode_failed"
                                              message:@"逆地理编码未返回结果。"
                                              details:nil]);
        }
        [self finish];
        return;
    }
    AMapAddressComponent *component = regeocode.addressComponent;
    NSMutableDictionary *value = [NSMutableDictionary dictionary];
    value[@"location"] = @[@(request.location.latitude), @(request.location.longitude)];
    AMapPut(value, @"formattedAddress", regeocode.formattedAddress);
    AMapPut(value, @"country", component.country);
    AMapPut(value, @"province", component.province);
    AMapPut(value, @"city", component.city);
    AMapPut(value, @"district", component.district);
    AMapPut(value, @"township", component.township);
    AMapPut(value, @"neighborhood", component.neighborhood);
    AMapPut(value, @"building", component.building);
    AMapPut(value, @"adCode", component.adcode);
    AMapPut(value, @"cityCode", component.citycode);
    AMapPut(value, @"townCode", component.towncode);
    AMapPut(value, @"street", component.streetNumber.street);
    AMapPut(value, @"number", component.streetNumber.number);
    AMapPut(value, @"placeName", regeocode.pois.firstObject.name);
    FlutterResult pendingResult = self.result;
    if (pendingResult != nil) {
        pendingResult(value);
    }
    [self finish];
}

- (void)AMapSearchRequest:(id)request didFailWithError:(NSError *)error {
    FlutterResult pendingResult = self.result;
    if (pendingResult != nil) {
        NSString *code = [request isKindOfClass:AMapReGeocodeSearchRequest.class]
            ? @"reverse_geocode_failed" : @"geocode_failed";
        pendingResult([FlutterError errorWithCode:code
                                          message:error.localizedDescription
                                          details:@(error.code)]);
    }
    [self finish];
}

- (void)finish {
    self.search.delegate = nil;
    if (self.completion != nil) {
        self.completion(self);
    }
    self.result = nil;
    self.completion = nil;
}

@end

@implementation AMapPoiSearchOperation

- (instancetype)initWithResult:(FlutterResult)result
                     completion:(void (^)(AMapPoiSearchOperation *operation))completion {
    self = [super init];
    if (self) {
        _result = [result copy];
        _completion = [completion copy];
        _search = [[AMapSearchAPI alloc] init];
        _search.delegate = self;
    }
    return self;
}

- (void)startWithArguments:(NSDictionary *)arguments {
    NSString *mode = [arguments[@"mode"] isKindOfClass:NSString.class]
        ? arguments[@"mode"] : @"keyword";
    NSString *keyword = AMapTrimmedString(arguments[@"keyword"]) ?: @"";
    NSString *types = AMapTrimmedString(arguments[@"types"]);
    NSString *city = AMapTrimmedString(arguments[@"city"]);
    NSInteger page = [arguments[@"page"] isKindOfClass:NSNumber.class]
        ? [arguments[@"page"] integerValue] : 1;
    NSInteger pageSize = [arguments[@"pageSize"] isKindOfClass:NSNumber.class]
        ? [arguments[@"pageSize"] integerValue] : 20;
    BOOL distanceSort = [arguments[@"distanceSort"] isKindOfClass:NSNumber.class]
        ? [arguments[@"distanceSort"] boolValue] : YES;
    NSInteger showFields = [arguments[@"showFields"] isKindOfClass:NSNumber.class]
        ? [arguments[@"showFields"] integerValue] : 0;
    BOOL cityLimit = [arguments[@"cityLimit"] isKindOfClass:NSNumber.class]
        ? [arguments[@"cityLimit"] boolValue] : NO;
    if (page < 1 || page > 100) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"页码必须在 1 到 100 之间。"
                   details:nil];
        return;
    }
    if (pageSize < 1 || pageSize > 25) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"每页数量必须在 1 到 25 之间。"
                   details:nil];
        return;
    }
    if (keyword.length == 0 && types.length == 0) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"keyword 和 types 至少提供一个。"
                   details:nil];
        return;
    }
    if (![mode isEqualToString:@"keyword"] &&
        ![mode isEqualToString:@"around"]) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"不支持的 POI 查询类型。"
                   details:nil];
        return;
    }

    AMapGeoPoint *location = [self pointFromValue:arguments[@"location"]];
    NSInteger radius = [arguments[@"radius"] isKindOfClass:NSNumber.class]
        ? [arguments[@"radius"] integerValue] : 3000;
    if ([mode isEqualToString:@"around"] && location == nil) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"周边查询必须提供中心坐标。"
                   details:nil];
        return;
    }
    if ([mode isEqualToString:@"around"] && (radius < 1 || radius > 50000)) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"查询半径必须在 1 到 50000 米之间。"
                   details:nil];
        return;
    }

    if ([mode isEqualToString:@"keyword"] && cityLimit && city.length == 0) {
        [self failWithCode:@"poi_search_invalid_argument"
                   message:@"cityLimit 为 true 时必须提供 city。"
                   details:nil];
        return;
    }

    // Keep the iOS implementation on the POI 2.0 (no-suffix) API so its
    // request and field semantics line up with Android's PoiSearchV2.
    // `building` and `special` are accepted by the shared Dart options but
    // have no equivalent on this iOS API and are therefore ignored here.
    // `queryLanguage` is also intentionally ignored; the iOS SDK uses its
    // current language configuration for the no-suffix POI 2.0 request.
    AMapPOISearchBaseRequest *request = nil;
    if ([mode isEqualToString:@"keyword"]) {
        AMapPOIKeywordsSearchRequest *keywordRequest =
            [[AMapPOIKeywordsSearchRequest alloc] init];
        keywordRequest.keywords = keyword.length > 0 ? keyword : nil;
        keywordRequest.city = city;
        keywordRequest.cityLimit = cityLimit;
        keywordRequest.location = location;
        request = keywordRequest;
    } else if ([mode isEqualToString:@"around"]) {
        AMapPOIAroundSearchRequest *aroundRequest =
            [[AMapPOIAroundSearchRequest alloc] init];
        aroundRequest.keywords = keyword.length > 0 ? keyword : nil;
        aroundRequest.city = city;
        aroundRequest.location = location;
        aroundRequest.radius = radius;
        request = aroundRequest;
    }

    request.types = types;
    request.sortrule = distanceSort ? 0 : 1;
    request.offset = pageSize;
    request.page = page;
    request.showFieldsType = AMapPoiShowFieldsTypeFromMask(showFields);

    self.showFields = showFields;
    self.request = request;
    self.distanceOrigin = [mode isEqualToString:@"around"] ? location : nil;

    NSDictionary *customParams = [arguments[@"customParams"] isKindOfClass:NSDictionary.class]
        ? arguments[@"customParams"] : nil;
    if (customParams != nil) {
        NSMutableDictionary *sanitized = [NSMutableDictionary dictionary];
        [customParams enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) {
                sanitized[key] = value;
            }
        }];
        self.search.customParams = sanitized;
    }

    if ([request isKindOfClass:AMapPOIKeywordsSearchRequest.class]) {
        [self.search AMapPOIKeywordsSearch:(AMapPOIKeywordsSearchRequest *)request];
    } else {
        [self.search AMapPOIAroundSearch:(AMapPOIAroundSearchRequest *)request];
    }
}

- (AMapGeoPoint *)pointFromValue:(id)value {
    if (![value isKindOfClass:NSArray.class] || [value count] < 2 ||
        ![value[0] isKindOfClass:NSNumber.class] ||
        ![value[1] isKindOfClass:NSNumber.class]) {
        return nil;
    }
    return [AMapGeoPoint locationWithLatitude:[value[0] doubleValue]
                                    longitude:[value[1] doubleValue]];
}

- (void)failWithMessage:(NSString *)message details:(id)details {
    [self failWithCode:@"poi_search_failed" message:message details:details];
}

- (void)failWithCode:(NSString *)code message:(NSString *)message details:(id)details {
    FlutterResult pendingResult = self.result;
    self.result = nil;
    if (pendingResult != nil) {
        pendingResult([FlutterError errorWithCode:code
                                          message:message
                                          details:details]);
    }
    [self finish];
}

- (void)cancelForPrivacyRevocation {
    [self cancelWithCode:@"privacy_not_agreed" message:@"用户已撤回高德隐私授权。"];
}

- (void)cancelWithCode:(NSString *)code message:(NSString *)message {
    FlutterResult pendingResult = self.result;
    self.result = nil;
    self.search.delegate = nil;
    [self.search cancelAllRequests];
    if (pendingResult != nil) {
        pendingResult([FlutterError errorWithCode:code
                                          message:message
                                          details:nil]);
    }
    [self finish];
}

- (void)finishWithPage:(NSInteger)page
              pageSize:(NSInteger)pageSize
                 count:(NSInteger)count
                  pois:(NSArray<AMapPOI *> *)rawPois {
    NSMutableDictionary *value = [NSMutableDictionary dictionary];
    value[@"totalCount"] = @(count);
    value[@"page"] = @(page);
    value[@"pageSize"] = @(pageSize);
    NSMutableArray *pois = [NSMutableArray arrayWithCapacity:rawPois.count];
    BOOL includeIndoor = self.showFields < 0 || (self.showFields & (1 << 3)) != 0;
    for (AMapPOI *poi in rawPois) {
        if (poi.location != nil) {
            [pois addObject:AMapPoiToMap(poi, includeIndoor, self.distanceOrigin)];
        }
    }
    value[@"pois"] = pois;
    FlutterResult pendingResult = self.result;
    if (pendingResult != nil) {
        pendingResult(value);
    }
    [self finish];
}

- (void)onPOISearchDone:(AMapPOISearchBaseRequest *)request
               response:(AMapPOISearchResponse *)response {
    if (request == nil || response == nil) {
        [self failWithMessage:@"POI 搜索未返回有效结果。" details:nil];
        return;
    }
    [self finishWithPage:request.page
                pageSize:request.offset
                   count:response.count
                    pois:response.pois];
}

- (void)AMapSearchRequest:(id)request didFailWithError:(NSError *)error {
    [self failWithMessage:error.localizedDescription ?: @"POI 搜索失败。"
                  details:@(error.code)];
}

- (void)finish {
    self.search.delegate = nil;
    if (self.completion != nil) {
        self.completion(self);
    }
    self.result = nil;
    self.completion = nil;
    self.request = nil;
}

@end
