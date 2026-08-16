#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 统一管理地图、定位和搜索 SDK 的隐私合规状态。
@interface AMapPrivacyManager : NSObject

/// 三项隐私声明是否均已满足。
+ (BOOL)isPrivacyAllowed:(NSDictionary *)statement;

/// 将同一份隐私声明同步给地图、定位和搜索 SDK。
+ (void)updatePrivacyWithStatement:(NSDictionary *)statement;

@end

NS_ASSUME_NONNULL_END
