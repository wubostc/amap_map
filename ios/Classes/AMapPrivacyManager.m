#import "AMapPrivacyManager.h"

#import <AMapLocationKit/AMapLocationKit.h>
#import <AMapSearchKit/AMapSearchKit.h>
#import <MAMapKit/MAMapKit.h>

@implementation AMapPrivacyManager

+ (BOOL)isPrivacyAllowed:(NSDictionary *)statement {
    return [statement[@"hasContains"] boolValue] &&
        [statement[@"hasShow"] boolValue] &&
        [statement[@"hasAgree"] boolValue];
}

+ (void)updatePrivacyWithStatement:(NSDictionary *)statement {
    if (![statement isKindOfClass:NSDictionary.class]) {
        return;
    }

    id hasContains = statement[@"hasContains"];
    id hasShow = statement[@"hasShow"];
    if ([hasContains isKindOfClass:NSNumber.class] &&
        [hasShow isKindOfClass:NSNumber.class]) {
        AMapPrivacyShowStatus showStatus = [hasShow boolValue]
            ? AMapPrivacyShowStatusDidShow : AMapPrivacyShowStatusNotShow;
        AMapPrivacyInfoStatus infoStatus = [hasContains boolValue]
            ? AMapPrivacyInfoStatusDidContain : AMapPrivacyInfoStatusNotContain;
        [MAMapView updatePrivacyShow:showStatus privacyInfo:infoStatus];
        [AMapLocationManager updatePrivacyShow:showStatus privacyInfo:infoStatus];
        [AMapSearchAPI updatePrivacyShow:showStatus privacyInfo:infoStatus];
    }

    id hasAgree = statement[@"hasAgree"];
    if ([hasAgree isKindOfClass:NSNumber.class]) {
        AMapPrivacyAgreeStatus agreeStatus = [hasAgree boolValue]
            ? AMapPrivacyAgreeStatusDidAgree : AMapPrivacyAgreeStatusNotAgree;
        [MAMapView updatePrivacyAgree:agreeStatus];
        [AMapLocationManager updatePrivacyAgree:agreeStatus];
        [AMapSearchAPI updatePrivacyAgree:agreeStatus];
    }
}

@end
