//
//  AMapMarkerIconJsonRenderer.h
//  amap_map2
//
//  Created by 913721086@qq.com on 2026/7/13.
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMapMarkerIconJsonRenderer : NSObject

+ (nullable UIImage *)imageFromRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                                 iconMap:(NSDictionary *)iconMap;

@end

NS_ASSUME_NONNULL_END
