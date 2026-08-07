//
//  AMapMarkerIconJsonRenderer.m
//  amap_map2
//
//  Created by 913721086@qq.com on 2026/7/13.
//

#import "AMapMarkerIconJsonRenderer.h"
#import <QuartzCore/QuartzCore.h>

@interface AMapMarkerIconRenderedNode : NSObject

@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGSize size;
@property (nonatomic, strong) NSDictionary *style;

@end

@implementation AMapMarkerIconRenderedNode
@end

typedef struct {
    CGFloat left;
    CGFloat top;
    CGFloat right;
    CGFloat bottom;
} AMapMarkerIconEdges;

static const NSUInteger AMapMarkerIconMaxBitmapBytes = 2U * 1024U * 1024U;
static const NSUInteger AMapMarkerIconArgbBytesPerPixel = 4U;

@implementation AMapMarkerIconJsonRenderer

+ (nullable UIImage *)imageFromRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
                                 iconMap:(NSDictionary *)iconMap {
    if (![iconMap isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *viewNode = [self dictionaryFromObject:iconMap[@"view"]];
    if (viewNode.count == 0 && [iconMap[@"type"] isKindOfClass:[NSString class]]) {
        viewNode = iconMap;
    }
    if (![self isRootLayoutNode:viewNode]) {
        return [self emptyImage];
    }

    AMapMarkerIconRenderedNode *rendered = [self renderedNodeFromNode:viewNode
                                                            registrar:registrar];
    CGSize size = CGSizeMake(MAX(1.0, ceil(rendered.size.width)),
                             MAX(1.0, ceil(rendered.size.height)));
    CGFloat scale = UIScreen.mainScreen.scale;
    if (![self isRenderSizeWithinBitmapLimit:size scale:scale]) {
        return [self emptyImage];
    }
    rendered.view.frame = CGRectMake(0, 0, size.width, size.height);
    rendered.view.backgroundColor = rendered.view.backgroundColor ?: UIColor.clearColor;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = scale;
    if (@available(iOS 12.0, *)) {
        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    }
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [rendered.view.layer renderInContext:context.CGContext];
    }];
}

+ (AMapMarkerIconRenderedNode *)renderedNodeFromNode:(NSDictionary *)node
                                          registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    NSString *type = [[self stringFromObject:node[@"type"] defaultValue:@"stack"] lowercaseString];
    NSDictionary *style = [self dictionaryFromObject:node[@"style"]];

    if ([type isEqualToString:@"row"]) {
        return [self renderedRowFromNode:node style:style registrar:registrar];
    }
    if ([type isEqualToString:@"column"]) {
        return [self renderedColumnFromNode:node style:style registrar:registrar];
    }
    if ([type isEqualToString:@"stack"] || [type isEqualToString:@"container"]) {
        return [self renderedStackFromNode:node
                                     style:style
                                 registrar:registrar
                             appliesPadding:[type isEqualToString:@"container"]];
    }
    if ([type isEqualToString:@"text"]) {
        return [self renderedTextFromNode:node style:style];
    }
    if ([type isEqualToString:@"image"]) {
        return [self renderedImageFromNode:node style:style registrar:registrar];
    }
    if ([type isEqualToString:@"space"]) {
        return [self renderedSpaceFromStyle:style];
    }

    return [self renderedSpaceFromStyle:style];
}

+ (AMapMarkerIconRenderedNode *)renderedRowFromNode:(NSDictionary *)node
                                             style:(NSDictionary *)style
                                         registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    NSArray<AMapMarkerIconRenderedNode *> *children = [self renderedChildrenFromNode:node
                                                                           registrar:registrar];

    CGFloat contentWidth = 0;
    CGFloat contentHeight = 0;
    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        contentWidth += margin.left + child.size.width + margin.right;
        contentHeight = MAX(contentHeight, margin.top + child.size.height + margin.bottom);
    }

    CGSize size = CGSizeMake(MAX(0, contentWidth), MAX(0, contentHeight));
    CGFloat x = 0;
    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        CGPoint origin = [self originForChildSize:child.size
                                           margin:margin
                                           inRect:CGRectMake(0, 0, size.width, size.height)
                                        alignment:style[@"alignment"]];
        child.view.frame = CGRectMake(x + margin.left, origin.y, child.size.width, child.size.height);
        [view addSubview:child.view];
        x += margin.left + child.size.width + margin.right;
    }

    return [self renderedNodeWithView:view size:size style:style];
}

+ (AMapMarkerIconRenderedNode *)renderedColumnFromNode:(NSDictionary *)node
                                                style:(NSDictionary *)style
                                            registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    NSArray<AMapMarkerIconRenderedNode *> *children = [self renderedChildrenFromNode:node
                                                                           registrar:registrar];

    CGFloat contentWidth = 0;
    CGFloat contentHeight = 0;
    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        contentWidth = MAX(contentWidth, margin.left + child.size.width + margin.right);
        contentHeight += margin.top + child.size.height + margin.bottom;
    }

    CGSize size = CGSizeMake(MAX(0, contentWidth), MAX(0, contentHeight));
    CGFloat y = 0;
    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        CGPoint origin = [self originForChildSize:child.size
                                           margin:margin
                                           inRect:CGRectMake(0, 0, size.width, size.height)
                                        alignment:style[@"alignment"]];
        child.view.frame = CGRectMake(origin.x, y + margin.top, child.size.width, child.size.height);
        [view addSubview:child.view];
        y += margin.top + child.size.height + margin.bottom;
    }

    return [self renderedNodeWithView:view size:size style:style];
}

+ (AMapMarkerIconRenderedNode *)renderedStackFromNode:(NSDictionary *)node
                                               style:(NSDictionary *)style
                                           registrar:(NSObject<FlutterPluginRegistrar> *)registrar
                                     appliesPadding:(BOOL)appliesPadding {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    [self applyBoxStyle:style toView:view];
    AMapMarkerIconEdges padding = appliesPadding ? [self edgesFromObject:style[@"padding"]] : (AMapMarkerIconEdges){0, 0, 0, 0};
    NSArray<AMapMarkerIconRenderedNode *> *children = [self renderedChildrenFromNode:node
                                                                           registrar:registrar];

    CGFloat contentWidth = 0;
    CGFloat contentHeight = 0;
    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        contentWidth = MAX(contentWidth, margin.left + child.size.width + margin.right);
        contentHeight = MAX(contentHeight, margin.top + child.size.height + margin.bottom);
    }

    CGFloat measuredWidth = padding.left + contentWidth + padding.right;
    CGFloat measuredHeight = padding.top + contentHeight + padding.bottom;
    CGFloat width = [self sizeFromObject:style[@"width"] defaultValue:measuredWidth];
    CGFloat height = [self sizeFromObject:style[@"height"] defaultValue:measuredHeight];
    CGSize size = CGSizeMake(MAX(0, width), MAX(0, height));
    CGRect contentRect = CGRectMake(padding.left,
                                    padding.top,
                                    MAX(0, size.width - padding.left - padding.right),
                                    MAX(0, size.height - padding.top - padding.bottom));

    for (AMapMarkerIconRenderedNode *child in children) {
        AMapMarkerIconEdges margin = [self edgesFromObject:child.style[@"margin"]];
        CGPoint origin = [self originForChildSize:child.size
                                           margin:margin
                                          inRect:contentRect
                                       alignment:style[@"alignment"]];
        child.view.frame = CGRectMake(origin.x,
                                      origin.y,
                                      child.size.width,
                                      child.size.height);
        [view addSubview:child.view];
    }

    return [self renderedNodeWithView:view size:size style:style];
}

+ (AMapMarkerIconRenderedNode *)renderedTextFromNode:(NSDictionary *)node style:(NSDictionary *)style {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectZero];
    [self applyBoxStyle:style toView:wrapper];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = [self stringFromObject:node[@"text"] defaultValue:@""];
    UIColor *textColor = [self colorFromObject:style[@"textColor"] defaultColor:UIColor.blackColor];
    label.textColor = textColor;
    label.font = [self fontFromStyle:style];
    label.textAlignment = [self textAlignmentFromAlignment:style[@"alignment"]];
    label.numberOfLines = [self numberOfLinesFromStyle:style];
    NSString *ellipsize = [self stringFromObject:style[@"ellipsize"] defaultValue:nil];
    if ([ellipsize isEqualToString:@"start"]) {
        label.lineBreakMode = NSLineBreakByTruncatingHead;
    } else if ([ellipsize isEqualToString:@"middle"]) {
        label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    } else {
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    AMapMarkerIconEdges padding = [self edgesFromObject:style[@"padding"]];
    CGFloat explicitWidth = [self sizeFromObject:style[@"width"] defaultValue:NAN];
    CGFloat explicitHeight = [self sizeFromObject:style[@"height"] defaultValue:NAN];
    CGFloat maxLabelWidth = isnan(explicitWidth) ? CGFLOAT_MAX : MAX(0, explicitWidth - padding.left - padding.right);
    CGSize labelSize = [label sizeThatFits:CGSizeMake(maxLabelWidth, CGFLOAT_MAX)];
    NSNumber *minLines = [self numberFromObject:style[@"minLines"]];
    if (minLines.integerValue > 0) {
        labelSize.height = MAX(labelSize.height, label.font.lineHeight * minLines.integerValue);
    }
    CGFloat width = isnan(explicitWidth) ? padding.left + labelSize.width + padding.right : explicitWidth;
    CGFloat height = isnan(explicitHeight) ? padding.top + labelSize.height + padding.bottom : explicitHeight;
    CGFloat contentHeight = MAX(0, height - padding.top - padding.bottom);
    CGFloat renderedLabelHeight = MIN(labelSize.height, contentHeight);
    CGFloat labelY = padding.top + [self verticalOffsetForChild:renderedLabelHeight
                                                       available:contentHeight
                                                      alignment:style[@"alignment"]];

    wrapper.frame = CGRectMake(0, 0, MAX(0, width), MAX(0, height));
    label.frame = CGRectMake(padding.left,
                             labelY,
                             MAX(0, width - padding.left - padding.right),
                             renderedLabelHeight);
    [wrapper addSubview:label];

    return [self renderedNodeWithView:wrapper size:wrapper.frame.size style:style];
}

+ (AMapMarkerIconRenderedNode *)renderedImageFromNode:(NSDictionary *)node
                                               style:(NSDictionary *)style
                                           registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    UIImage *image = [self imageFromSource:node[@"src"] registrar:registrar];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    CGFloat width = [self sizeFromObject:style[@"width"] defaultValue:(image ? image.size.width : 0)];
    CGFloat height = [self sizeFromObject:style[@"height"] defaultValue:(image ? image.size.height : 0)];
    CGSize size = CGSizeMake(MAX(0, width), MAX(0, height));
    imageView.frame = CGRectMake(0, 0, size.width, size.height);
    return [self renderedNodeWithView:imageView size:size style:style];
}

+ (AMapMarkerIconRenderedNode *)renderedSpaceFromStyle:(NSDictionary *)style {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat width = [self sizeFromObject:style[@"width"] defaultValue:0];
    CGFloat height = [self sizeFromObject:style[@"height"] defaultValue:0];
    return [self renderedNodeWithView:view size:CGSizeMake(MAX(0, width), MAX(0, height)) style:style];
}

+ (NSArray<AMapMarkerIconRenderedNode *> *)renderedChildrenFromNode:(NSDictionary *)node
                                                          registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    NSMutableArray<AMapMarkerIconRenderedNode *> *children = [NSMutableArray array];
    NSDictionary *child = [self dictionaryFromObject:node[@"child"]];
    NSString *type = [[self stringFromObject:node[@"type"] defaultValue:@""] lowercaseString];
    if ([type isEqualToString:@"container"] && child.count > 0) {
        [children addObject:[self renderedNodeFromNode:child
                                             registrar:registrar]];
    }
    if ([type isEqualToString:@"container"]) {
        return children;
    }
    NSArray *rawChildren = [self arrayFromObject:node[@"children"]];
    for (id rawChild in rawChildren) {
        NSDictionary *childNode = [self dictionaryFromObject:rawChild];
        if (childNode.count > 0) {
            [children addObject:[self renderedNodeFromNode:childNode
                                                 registrar:registrar]];
        }
    }
    return children;
}

+ (AMapMarkerIconRenderedNode *)renderedNodeWithView:(UIView *)view
                                               size:(CGSize)size
                                              style:(NSDictionary *)style {
    AMapMarkerIconRenderedNode *node = [[AMapMarkerIconRenderedNode alloc] init];
    node.view = view;
    node.size = size;
    node.style = style ?: @{};
    view.frame = CGRectMake(0, 0, size.width, size.height);
    return node;
}

+ (BOOL)isRenderSizeWithinBitmapLimit:(CGSize)size scale:(CGFloat)scale {
    if (!isfinite(size.width) || !isfinite(size.height) || !isfinite(scale) ||
        size.width <= 0 || size.height <= 0 || scale <= 0) {
        return NO;
    }

    double widthInPixels = ceil(size.width * scale);
    double heightInPixels = ceil(size.height * scale);
    if (!isfinite(widthInPixels) || !isfinite(heightInPixels) ||
        widthInPixels <= 0 || heightInPixels <= 0) {
        return NO;
    }

    double maxPixels = (double)AMapMarkerIconMaxBitmapBytes / AMapMarkerIconArgbBytesPerPixel;
    return widthInPixels <= maxPixels / heightInPixels;
}

+ (void)applyBoxStyle:(NSDictionary *)style toView:(UIView *)view {
    UIColor *backgroundColor = [self colorFromObject:style[@"backgroundColor"] defaultColor:nil];
    if (backgroundColor) {
        view.backgroundColor = backgroundColor;
    }
    NSNumber *radius = [self numberFromObject:style[@"radius"]];
    if (radius) {
        view.layer.cornerRadius = radius.doubleValue;
        view.layer.masksToBounds = YES;
    }
    UIColor *borderColor = [self colorFromObject:style[@"borderColor"] defaultColor:nil];
    NSNumber *borderWidth = [self numberFromObject:style[@"borderWidth"]];
    if (borderColor && borderWidth.doubleValue > 0) {
        view.layer.borderColor = borderColor.CGColor;
        view.layer.borderWidth = borderWidth.doubleValue;
    }
}

+ (nullable UIImage *)imageFromSource:(id)source registrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    NSArray *data = [self arrayFromObject:source];
    if (data.count < 2 || !([data[0] isEqual:@"fromAsset"])) {
        return nil;
    }
    NSString *assetName = [self stringFromObject:data[1] defaultValue:nil];
    if (assetName.length == 0) {
        return nil;
    }
    NSString *lookupKey = nil;
    if (data.count == 2) {
        lookupKey = [registrar lookupKeyForAsset:assetName];
    } else {
        NSString *package = [self stringFromObject:data[2] defaultValue:nil];
        lookupKey = [registrar lookupKeyForAsset:assetName fromPackage:package];
    }
    return [UIImage imageNamed:lookupKey];
}

+ (UIFont *)fontFromStyle:(NSDictionary *)style {
    CGFloat size = [self numberFromObject:style[@"textSize"]].doubleValue;
    if (size <= 0) {
        size = 14.0;
    }

    NSString *textStyle = [[self stringFromObject:style[@"textStyle"] defaultValue:@""] lowercaseString];
    NSString *fontWeight = [[self stringFromObject:style[@"fontWeight"] defaultValue:@""] lowercaseString];
    BOOL bold = [textStyle containsString:@"bold"] ||
                [fontWeight isEqualToString:@"bold"] ||
                [fontWeight isEqualToString:@"700"] ||
                [fontWeight isEqualToString:@"800"] ||
                [fontWeight isEqualToString:@"900"];
    BOOL italic = [textStyle containsString:@"italic"];
    UIFontDescriptorSymbolicTraits traits = 0;
    if (bold) {
        traits |= UIFontDescriptorTraitBold;
    }
    if (italic) {
        traits |= UIFontDescriptorTraitItalic;
    }
    UIFont *font = [UIFont systemFontOfSize:size];
    if (traits != 0) {
        UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
        if (descriptor) {
            font = [UIFont fontWithDescriptor:descriptor size:size];
        }
    }
    return font;
}

+ (NSInteger)numberOfLinesFromStyle:(NSDictionary *)style {
    if ([self boolFromObject:style[@"singleLine"] defaultValue:NO]) {
        return 1;
    }
    NSNumber *maxLines = [self numberFromObject:style[@"maxLines"]];
    if (maxLines.integerValue > 0) {
        return maxLines.integerValue;
    }
    return 0;
}

+ (NSTextAlignment)textAlignmentFromAlignment:(id)alignment {
    NSString *value = [self canonicalAlignmentFromObject:alignment];
    if ([self hasRightAlignment:value]) {
        return NSTextAlignmentRight;
    }
    if ([self hasHorizontalCenterAlignment:value]) {
        return NSTextAlignmentCenter;
    }
    return NSTextAlignmentLeft;
}

+ (CGPoint)originForChildSize:(CGSize)childSize
                        margin:(AMapMarkerIconEdges)margin
                        inRect:(CGRect)rect
                     alignment:(id)alignment {
    NSString *value = [self canonicalAlignmentFromObject:alignment];
    CGFloat x = rect.origin.x + margin.left;
    CGFloat y = rect.origin.y + margin.top;

    if ([self hasRightAlignment:value]) {
        x += rect.size.width - childSize.width - margin.left - margin.right;
    } else if ([self hasHorizontalCenterAlignment:value]) {
        x += (rect.size.width - childSize.width) / 2.0 - margin.right;
    }

    if ([self hasBottomAlignment:value]) {
        y += rect.size.height - childSize.height - margin.top - margin.bottom;
    } else if ([self hasVerticalCenterAlignment:value]) {
        y += (rect.size.height - childSize.height) / 2.0 - margin.bottom;
    }

    return CGPointMake(x, y);
}

+ (CGFloat)verticalOffsetForChild:(CGFloat)child available:(CGFloat)available alignment:(id)alignment {
    NSString *value = [self canonicalAlignmentFromObject:alignment];
    if ([self hasBottomAlignment:value]) {
        return MAX(0, available - child);
    }
    if ([self hasVerticalCenterAlignment:value]) {
        return MAX(0, (available - child) / 2.0);
    }
    return 0;
}

+ (NSString *)canonicalAlignmentFromObject:(id)alignment {
    NSString *value = [[self stringFromObject:alignment defaultValue:@""] lowercaseString];
    if ([value isEqualToString:@"center"] ||
        [value isEqualToString:@"top|left"] ||
        [value isEqualToString:@"top|right"] ||
        [value isEqualToString:@"bottom|left"] ||
        [value isEqualToString:@"bottom|right"] ||
        [value isEqualToString:@"top|center"] ||
        [value isEqualToString:@"bottom|center"] ||
        [value isEqualToString:@"center|left"] ||
        [value isEqualToString:@"center|right"]) {
        return value;
    }
    return @"";
}

+ (BOOL)hasRightAlignment:(NSString *)alignment {
    return [alignment isEqualToString:@"top|right"] ||
           [alignment isEqualToString:@"bottom|right"] ||
           [alignment isEqualToString:@"center|right"];
}

+ (BOOL)hasHorizontalCenterAlignment:(NSString *)alignment {
    return [alignment isEqualToString:@"center"] ||
           [alignment isEqualToString:@"top|center"] ||
           [alignment isEqualToString:@"bottom|center"];
}

+ (BOOL)hasBottomAlignment:(NSString *)alignment {
    return [alignment isEqualToString:@"bottom|left"] ||
           [alignment isEqualToString:@"bottom|right"] ||
           [alignment isEqualToString:@"bottom|center"];
}

+ (BOOL)hasVerticalCenterAlignment:(NSString *)alignment {
    return [alignment isEqualToString:@"center"] ||
           [alignment isEqualToString:@"center|left"] ||
           [alignment isEqualToString:@"center|right"];
}

+ (CGFloat)sizeFromObject:(id)object defaultValue:(CGFloat)defaultValue {
    if (!object || object == NSNull.null) {
        return defaultValue;
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [object doubleValue];
    }
    return defaultValue;
}

+ (AMapMarkerIconEdges)edgesFromObject:(id)object {
    if (!object || object == NSNull.null) {
        return (AMapMarkerIconEdges){0, 0, 0, 0};
    }
    if ([object isKindOfClass:[NSNumber class]] || [object isKindOfClass:[NSString class]]) {
        CGFloat value = [self sizeFromObject:object defaultValue:0];
        return (AMapMarkerIconEdges){value, value, value, value};
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *list = (NSArray *)object;
        if (list.count == 1) {
            CGFloat value = [self sizeFromObject:list[0] defaultValue:0];
            return (AMapMarkerIconEdges){value, value, value, value};
        }
        if (list.count == 2) {
            CGFloat horizontal = [self sizeFromObject:list[0] defaultValue:0];
            CGFloat vertical = [self sizeFromObject:list[1] defaultValue:0];
            return (AMapMarkerIconEdges){horizontal, vertical, horizontal, vertical};
        }
        if (list.count == 3) {
            CGFloat left = [self sizeFromObject:list[0] defaultValue:0];
            CGFloat vertical = [self sizeFromObject:list[1] defaultValue:0];
            CGFloat right = [self sizeFromObject:list[2] defaultValue:0];
            return (AMapMarkerIconEdges){left, vertical, right, vertical};
        }
        if (list.count >= 4) {
            return (AMapMarkerIconEdges){
                [self sizeFromObject:list[0] defaultValue:0],
                [self sizeFromObject:list[1] defaultValue:0],
                [self sizeFromObject:list[2] defaultValue:0],
                [self sizeFromObject:list[3] defaultValue:0]
            };
        }
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *map = (NSDictionary *)object;
        CGFloat horizontal = [self sizeFromObject:map[@"horizontal"] defaultValue:0];
        CGFloat vertical = [self sizeFromObject:map[@"vertical"] defaultValue:0];
        CGFloat left = map[@"left"] ? [self sizeFromObject:map[@"left"] defaultValue:0] : horizontal;
        CGFloat top = map[@"top"] ? [self sizeFromObject:map[@"top"] defaultValue:0] : vertical;
        CGFloat right = map[@"right"] ? [self sizeFromObject:map[@"right"] defaultValue:0] : horizontal;
        CGFloat bottom = map[@"bottom"] ? [self sizeFromObject:map[@"bottom"] defaultValue:0] : vertical;
        return (AMapMarkerIconEdges){left, top, right, bottom};
    }
    return (AMapMarkerIconEdges){0, 0, 0, 0};
}

+ (UIColor *)colorFromObject:(id)object defaultColor:(UIColor *)defaultColor {
    if (![object isKindOfClass:[NSString class]]) {
        return defaultColor;
    }
    NSString *value = [(NSString *)object stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![value hasPrefix:@"#"]) {
        return defaultColor;
    }
    NSString *hex = [value substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) {
        return defaultColor;
    }
    unsigned int raw = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&raw] || !scanner.isAtEnd) {
        return defaultColor;
    }
    CGFloat a = 1.0;
    CGFloat r = 0;
    CGFloat g = 0;
    CGFloat b = 0;
    if (hex.length == 8) {
        a = ((raw & 0xFF000000) >> 24) / 255.0;
        r = ((raw & 0x00FF0000) >> 16) / 255.0;
        g = ((raw & 0x0000FF00) >> 8) / 255.0;
        b = (raw & 0x000000FF) / 255.0;
    } else if (hex.length == 6) {
        r = ((raw & 0xFF0000) >> 16) / 255.0;
        g = ((raw & 0x00FF00) >> 8) / 255.0;
        b = (raw & 0x0000FF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

+ (NSNumber *)numberFromObject:(id)object {
    if ([object isKindOfClass:[NSNumber class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSString class]]) {
        return @([(NSString *)object doubleValue]);
    }
    return nil;
}

+ (BOOL)boolFromObject:(id)object defaultValue:(BOOL)defaultValue {
    if ([object isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)object boolValue];
    }
    if ([object isKindOfClass:[NSString class]]) {
        NSString *value = [(NSString *)object lowercaseString];
        return [value isEqualToString:@"true"] || [value isEqualToString:@"1"] || [value isEqualToString:@"yes"];
    }
    return defaultValue;
}

+ (NSDictionary *)dictionaryFromObject:(id)object {
    return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

+ (NSArray *)arrayFromObject:(id)object {
    return [object isKindOfClass:[NSArray class]] ? object : @[];
}

+ (NSString *)stringFromObject:(id)object defaultValue:(NSString *)defaultValue {
    if (!object || object == NSNull.null) {
        return defaultValue;
    }
    if ([object isKindOfClass:[NSString class]]) {
        return object;
    }
    return nil;
}

+ (BOOL)isRootLayoutNode:(NSDictionary *)node {
    NSString *type = [[self stringFromObject:node[@"type"] defaultValue:@""] lowercaseString];
    return [type isEqualToString:@"container"] ||
           [type isEqualToString:@"row"] ||
           [type isEqualToString:@"column"] ||
           [type isEqualToString:@"stack"];
}

+ (UIImage *)emptyImage {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1) format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
    }];
}

@end
