#import "AMapServicesController.h"
#import "AMapPrivacyManager.h"

#import <AMapFoundationKit/AMapFoundationKit.h>
#import <AMapLocationKit/AMapLocationKit.h>
#import <AMapSearchKit/AMapSearchKit.h>
#import <CoreLocation/CoreLocation.h>

static NSString *const AMapLocationChannelName = @"amap_map2/location";
static NSString *const AMapGeocodingChannelName = @"amap_map2/geocoding";
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
@end

@interface AMapServicesController () <AMapLocationManagerDelegate>
@property(nonatomic, strong) FlutterMethodChannel *locationChannel;
@property(nonatomic, strong) FlutterMethodChannel *geocodingChannel;
@property(nonatomic, strong) FlutterEventChannel *locationEventChannel;
@property(nonatomic, copy, nullable) FlutterEventSink eventSink;
// 单次和连续定位隔离，单次请求不会停止正在运行的连续定位。
@property(nonatomic, strong, nullable) AMapLocationManager *continuousManager;
@property(nonatomic, strong, nullable) AMapLocationManager *singleManager;
@property(nonatomic, copy, nullable) FlutterResult singleResult;
@property(nonatomic, assign) NSTimeInterval eventInterval;
@property(nonatomic, assign) NSTimeInterval lastEventTime;
@property(nonatomic, strong) NSMutableSet<AMapGeocodeOperation *> *geocodeOperations;
@end

@implementation AMapServicesController

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _geocodeOperations = [NSMutableSet set];
        _locationChannel = [FlutterMethodChannel methodChannelWithName:AMapLocationChannelName
                                                       binaryMessenger:messenger];
        _geocodingChannel = [FlutterMethodChannel methodChannelWithName:AMapGeocodingChannelName
                                                         binaryMessenger:messenger];
        _locationEventChannel = [FlutterEventChannel eventChannelWithName:AMapLocationEventsChannelName
                                                           binaryMessenger:messenger];
        __weak typeof(self) weakSelf = self;
        FlutterMethodCallHandler handler = ^(FlutterMethodCall *call, FlutterResult result) {
            [weakSelf handleMethodCall:call result:result];
        };
        [_locationChannel setMethodCallHandler:handler];
        [_geocodingChannel setMethodCallHandler:handler];
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
    [self.locationEventChannel setStreamHandler:nil];
    [self stopContinuousLocation];
    [self.singleManager stopUpdatingLocation];
    self.singleManager = nil;
    for (AMapGeocodeOperation *operation in self.geocodeOperations.copy) {
        [operation.search cancelAllRequests];
    }
    [self.geocodeOperations removeAllObjects];
    self.eventSink = nil;
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
    FlutterResult pendingResult = self.result;
    self.result = nil;
    self.search.delegate = nil;
    [self.search cancelAllRequests];
    if (pendingResult != nil) {
        pendingResult([FlutterError errorWithCode:@"privacy_not_agreed"
                                          message:@"用户已撤回高德隐私授权。"
                                          details:nil]);
    }
    self.completion = nil;
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
