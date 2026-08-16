#import "AMapFlutterMapPlugin.h"
#import "AMapFlutterFactory.h"
#import "AMapServicesController.h"

static NSMutableArray<AMapServicesController *> *AMapServiceControllers;

@implementation AMapFlutterMapPlugin{
  NSObject<FlutterPluginRegistrar>* _registrar;
  FlutterMethodChannel* _channel;
  NSMutableDictionary* _mapControllers;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    if (AMapServiceControllers == nil) {
      AMapServiceControllers = [NSMutableArray array];
    }
    AMapServicesController *servicesController =
      [[AMapServicesController alloc] initWithMessenger:registrar.messenger];
    [AMapServiceControllers addObject:servicesController];
    AMapFlutterFactory* aMapFactory = [[AMapFlutterFactory alloc] initWithRegistrar:registrar];
    [registrar registerViewFactory:aMapFactory
                            withId:@"com.amap.flutter.map2"
  gestureRecognizersBlockingPolicy:
     FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded];
}

@end
