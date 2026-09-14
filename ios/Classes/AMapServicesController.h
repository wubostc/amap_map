#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapServicesController : NSObject <FlutterStreamHandler>

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (void)dispose;
/// Called by Flutter when the engine that owns this controller is destroyed.
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;

@end

NS_ASSUME_NONNULL_END
