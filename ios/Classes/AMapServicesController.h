#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapServicesController : NSObject <FlutterStreamHandler>

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
