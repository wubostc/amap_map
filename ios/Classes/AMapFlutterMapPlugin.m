#import "AMapFlutterMapPlugin.h"
#import "AMapFlutterFactory.h"
#import "AMapServicesController.h"

@implementation AMapFlutterMapPlugin{
  NSObject<FlutterPluginRegistrar>* _registrar;
  FlutterMethodChannel* _channel;
  NSMutableDictionary* _mapControllers;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    AMapServicesController *servicesController =
      [[AMapServicesController alloc] initWithMessenger:registrar.messenger];
    // Publishing gives the controller an engine-scoped lifetime and makes
    // Flutter call its detach hook for pending asynchronous requests.
    [registrar publish:servicesController];
    AMapFlutterFactory* aMapFactory = [[AMapFlutterFactory alloc] initWithRegistrar:registrar];
    [registrar registerViewFactory:aMapFactory
                            withId:@"com.amap.flutter.map2"
  gestureRecognizersBlockingPolicy:
     FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded];
}

@end
