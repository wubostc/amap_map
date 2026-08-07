// Declarative marker icon JSON schema.
// Author: 913721086@qq.com

import 'dart:ui' show Color;

import 'package:amap_map2/src/compatibility/color_extensions.dart';

/// Builds a platform-neutral, declarative marker icon description.
///
/// The generated map is consumed by Android and iOS native renderers through
/// the same platform-neutral schema.
///
/// Example:
/// ```dart
/// final icon = MarkerRender.icon(
///   view: MarkerRender.container(
///     style: const MarkerRenderContainerStyle(
///       alignment: MarkerRenderAlignment.center,
///     ),
///     child: MarkerRender.column(
///       children: [
///         MarkerRender.text(
///           '18',
///           style: const MarkerRenderTextStyle(
///             textColor: Color(0xFFFFFFFF),
///             textSize: 12,
///             textStyle: MarkerRenderTextStyleValue.bold,
///             backgroundColor: Color(0xFFE53935),
///             radius: 10,
///             padding: MarkerRenderInsets.fromLTRB(8, 2, 8, 2),
///             alignment: MarkerRenderAlignment.center,
///             includeFontPadding: false,
///           ),
///         ),
///         MarkerRender.space(height: 2),
///         MarkerRender.image(
///           const MarkerRenderAssetSource('assets/marker_icon.png'),
///           style: const MarkerRenderImageStyle(
///             width: 48,
///             height: 48,
///           ),
///         ),
///       ],
///     ),
///   ),
/// );
/// ```
class MarkerRender {
  MarkerRender._();

  /// Creates the root marker icon description.
  static MarkerRenderIcon icon({
    required MarkerRenderLayoutNode view,
  }) {
    return MarkerRenderIcon(view: view);
  }

  /// Creates a root or child container.
  ///
  /// A container can have fixed [MarkerRenderContainerStyle.width] and
  /// [MarkerRenderContainerStyle.height], or omit them to wrap its child
  /// content. It only supports [child].
  static MarkerRenderLayoutNode container({
    MarkerRenderContainerStyle? style,
    MarkerRenderNode? child,
  }) {
    return MarkerRenderGroupNode(
      type: MarkerRenderNodeType.container,
      style: style,
      child: child,
    );
  }

  /// Creates a horizontal child layout.
  static MarkerRenderLayoutNode row({
    MarkerRenderRowStyle? style,
    List<MarkerRenderNode> children = const <MarkerRenderNode>[],
  }) {
    return MarkerRenderGroupNode(
      type: MarkerRenderNodeType.row,
      style: style,
      children: children,
    );
  }

  /// Creates a vertical child layout.
  static MarkerRenderLayoutNode column({
    MarkerRenderColumnStyle? style,
    List<MarkerRenderNode> children = const <MarkerRenderNode>[],
  }) {
    return MarkerRenderGroupNode(
      type: MarkerRenderNodeType.column,
      style: style,
      children: children,
    );
  }

  /// Creates an overlapping child layout from [children].
  ///
  /// A stack requires [style] with explicit width and height, and does not
  /// support a singular `child` field.
  static MarkerRenderLayoutNode stack({
    required MarkerRenderStackStyle style,
    List<MarkerRenderNode> children = const <MarkerRenderNode>[],
  }) {
    return MarkerRenderGroupNode(
      type: MarkerRenderNodeType.stack,
      style: style,
      children: children,
    );
  }

  /// Creates a text node.
  static MarkerRenderNode text(
    String value, {
    MarkerRenderTextStyle? style,
  }) {
    return MarkerRenderTextNode(
      text: value,
      style: style,
    );
  }

  /// Creates an asset image node.
  static MarkerRenderNode image(
    MarkerRenderImageSource src, {
    required MarkerRenderImageStyle style,
  }) {
    return MarkerRenderImageNode(
      src: src,
      style: style,
    );
  }

  /// Creates fixed empty space.
  static MarkerRenderNode space({
    double? width,
    double? height,
  }) {
    return MarkerRenderSpaceNode(
      width: width,
      height: height,
    );
  }
}

/// A serializable marker icon root.
class MarkerRenderIcon {
  /// Creates a marker icon root.
  const MarkerRenderIcon({
    required this.view,
  });

  /// Root view node.
  final MarkerRenderLayoutNode view;

  /// Converts this icon into the platform-channel schema.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'view': view.toJson(),
    };
  }
}

/// Base class for all marker icon nodes.
abstract class MarkerRenderNode {
  /// Creates a marker icon node.
  const MarkerRenderNode();

  /// Converts this node into the platform-channel schema.
  Map<String, dynamic> toJson();
}

/// Base class for marker icon layout nodes.
abstract class MarkerRenderLayoutNode extends MarkerRenderNode {
  /// Creates a marker icon layout node.
  const MarkerRenderLayoutNode();
}

/// A layout node that can contain children.
class MarkerRenderGroupNode extends MarkerRenderLayoutNode {
  /// Creates a group node.
  const MarkerRenderGroupNode({
    required this.type,
    this.style,
    this.child,
    this.children = const <MarkerRenderNode>[],
  }) : assert(child == null || type == MarkerRenderNodeType.container);

  /// Layout type.
  final MarkerRenderNodeType type;

  /// Optional visual and layout style.
  final MarkerRenderNodeStyle? style;

  /// Optional single child. Only supported when [type] is `container`.
  final MarkerRenderNode? child;

  /// Child nodes. Unsupported for `container`.
  final List<MarkerRenderNode> children;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.value,
      if (style != null) 'style': style!.toJson(),
      if (type == MarkerRenderNodeType.container && child != null)
        'child': child!.toJson(),
      if (type != MarkerRenderNodeType.container)
        'children': children
            .map<Map<String, dynamic>>(
              (MarkerRenderNode node) => node.toJson(),
            )
            .toList(),
    };
  }
}

/// A text node.
class MarkerRenderTextNode extends MarkerRenderNode {
  /// Creates a text node.
  const MarkerRenderTextNode({
    required this.text,
    this.style,
  });

  /// Text content.
  final String text;

  /// Optional text style.
  final MarkerRenderTextStyle? style;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': MarkerRenderNodeType.text.value,
      'text': text,
      if (style != null) 'style': style!.toJson(),
    };
  }
}

/// An image node.
class MarkerRenderImageNode extends MarkerRenderNode {
  /// Creates an image node.
  const MarkerRenderImageNode({
    required this.src,
    required this.style,
  });

  /// Image source.
  final MarkerRenderImageSource src;

  /// Fixed image style.
  final MarkerRenderImageStyle style;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': MarkerRenderNodeType.image.value,
      'src': src.toJson(),
      'style': style.toJson(),
    };
  }
}

/// A fixed-size empty space node.
class MarkerRenderSpaceNode extends MarkerRenderNode {
  /// Creates a space node.
  const MarkerRenderSpaceNode({
    this.width,
    this.height,
  });

  /// Width.
  final double? width;

  /// Height.
  final double? height;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': MarkerRenderNodeType.space.value,
      'style': <String, dynamic>{
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      },
    };
  }
}

/// Base class for serializable marker icon styles.
abstract class MarkerRenderNodeStyle {
  const MarkerRenderNodeStyle();

  /// Converts this style into the platform-channel schema.
  Map<String, dynamic> toJson();
}

/// Style for `container` nodes.
class MarkerRenderContainerStyle extends MarkerRenderNodeStyle {
  /// Creates a container style.
  const MarkerRenderContainerStyle({
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.backgroundColor,
    this.radius,
    this.borderColor,
    this.borderWidth,
  });

  /// Width of the node.
  final double? width;

  /// Height of the node.
  final double? height;

  /// Inner spacing.
  final MarkerRenderInsets? padding;

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  /// Child/content alignment. Prefer this Flutter-friendly field for new code.
  final MarkerRenderAlignment? alignment;

  /// Background color.
  final Color? backgroundColor;

  /// Corner radius in logical units.
  final double? radius;

  /// Border color.
  final Color? borderColor;

  /// Border width in logical units.
  final double? borderWidth;

  /// Converts this style into the platform-channel schema.
  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (padding != null) 'padding': padding!.toJson(),
      if (margin != null) 'margin': margin!.toJson(),
      if (alignment != null) 'alignment': alignment!.value,
      if (backgroundColor != null)
        'backgroundColor': _colorToJson(backgroundColor!),
      if (radius != null) 'radius': radius,
      if (borderColor != null) 'borderColor': _colorToJson(borderColor!),
      if (borderWidth != null) 'borderWidth': borderWidth,
    };
  }
}

/// Style for `row` nodes.
class MarkerRenderRowStyle extends MarkerRenderNodeStyle {
  /// Creates a row style.
  const MarkerRenderRowStyle({
    this.margin,
    this.alignment = MarkerRenderAlignment.centerLeft,
  });

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  /// Child alignment inside the row.
  final MarkerRenderAlignment? alignment;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (margin != null) 'margin': margin!.toJson(),
      if (alignment != null) 'alignment': alignment!.value,
    };
  }
}

/// Style for `column` nodes.
class MarkerRenderColumnStyle extends MarkerRenderNodeStyle {
  /// Creates a column style.
  const MarkerRenderColumnStyle({
    this.margin,
    this.alignment = MarkerRenderAlignment.topCenter,
  });

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  /// Child alignment inside the column.
  final MarkerRenderAlignment? alignment;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (margin != null) 'margin': margin!.toJson(),
      if (alignment != null) 'alignment': alignment!.value,
    };
  }
}

/// Style for `stack` nodes.
class MarkerRenderStackStyle extends MarkerRenderNodeStyle {
  /// Creates a stack style.
  const MarkerRenderStackStyle({
    required this.width,
    required this.height,
    this.margin,
    this.alignment,
  });

  /// Width of the stack.
  final double width;

  /// Height of the stack.
  final double height;

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  /// Child alignment inside the stack.
  final MarkerRenderAlignment? alignment;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': width,
      'height': height,
      if (margin != null) 'margin': margin!.toJson(),
      if (alignment != null) 'alignment': alignment!.value,
    };
  }
}

/// Text-specific marker icon style.
class MarkerRenderTextStyle extends MarkerRenderNodeStyle {
  /// Creates a text marker icon style.
  const MarkerRenderTextStyle({
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.backgroundColor,
    this.radius,
    this.textColor,
    this.textSize,
    this.textStyle,
    this.fontWeight,
    this.maxLines,
    this.minLines,
    this.singleLine,
    this.ellipsize,
    this.includeFontPadding,
  });

  /// Width of the text node.
  final double? width;

  /// Height of the text node.
  final double? height;

  /// Inner spacing.
  final MarkerRenderInsets? padding;

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  /// Text alignment inside its box.
  final MarkerRenderAlignment? alignment;

  /// Background color.
  final Color? backgroundColor;

  /// Corner radius in logical units.
  final double? radius;

  /// Text color.
  final Color? textColor;

  /// Text size in sp.
  final double? textSize;

  /// Typeface style.
  final MarkerRenderTextStyleValue? textStyle;

  /// Font weight.
  final MarkerRenderFontWeight? fontWeight;

  /// Maximum line count.
  final int? maxLines;

  /// Minimum line count.
  final int? minLines;

  /// Whether text is restricted to one line.
  final bool? singleLine;

  /// Text overflow mode.
  final MarkerRenderEllipsize? ellipsize;

  /// Whether native font padding should be included.
  final bool? includeFontPadding;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (padding != null) 'padding': padding!.toJson(),
      if (margin != null) 'margin': margin!.toJson(),
      if (alignment != null) 'alignment': alignment!.value,
      if (backgroundColor != null)
        'backgroundColor': _colorToJson(backgroundColor!),
      if (radius != null) 'radius': radius,
      if (textColor != null) 'textColor': _colorToJson(textColor!),
      if (textSize != null) 'textSize': textSize,
      if (textStyle != null) 'textStyle': textStyle!.value,
      if (fontWeight != null) 'fontWeight': fontWeight!.value,
      if (maxLines != null) 'maxLines': maxLines,
      if (minLines != null) 'minLines': minLines,
      if (singleLine != null) 'singleLine': singleLine,
      if (ellipsize != null) 'ellipsize': ellipsize!.value,
      if (includeFontPadding != null) 'includeFontPadding': includeFontPadding,
    };
  }
}

/// Image-specific marker icon style.
class MarkerRenderImageStyle extends MarkerRenderNodeStyle {
  /// Creates an image marker icon style.
  const MarkerRenderImageStyle({
    required this.width,
    required this.height,
    this.margin,
  });

  /// Fixed image width in logical units.
  final double width;

  /// Fixed image height in logical units.
  final double height;

  /// Outer spacing.
  final MarkerRenderInsets? margin;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': width,
      'height': height,
      if (margin != null) 'margin': margin!.toJson(),
    };
  }
}

/// Describes edge insets used by padding and margin.
class MarkerRenderInsets {
  /// Same inset on all edges.
  const MarkerRenderInsets.all(double value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  /// Symmetric horizontal and vertical insets.
  const MarkerRenderInsets.symmetric({
    double horizontal = 0,
    double vertical = 0,
  })  : left = horizontal,
        top = vertical,
        right = horizontal,
        bottom = vertical;

  /// Insets from left, top, right, and bottom.
  const MarkerRenderInsets.fromLTRB(
    this.left,
    this.top,
    this.right,
    this.bottom,
  );

  /// Left inset in logical units.
  final double left;

  /// Top inset in logical units.
  final double top;

  /// Right inset in logical units.
  final double right;

  /// Bottom inset in logical units.
  final double bottom;

  /// Converts this inset into the platform-channel schema.
  List<double> toJson() {
    return <double>[left, top, right, bottom];
  }
}

/// Base class for supported image sources.
abstract class MarkerRenderImageSource {
  /// Creates an image source.
  const MarkerRenderImageSource();

  /// Converts this image source into the platform-channel schema.
  List<dynamic> toJson();
}

/// Asset image source.
class MarkerRenderAssetSource extends MarkerRenderImageSource {
  /// Creates an asset image source.
  const MarkerRenderAssetSource(
    this.assetName, {
    this.package,
  });

  /// Flutter asset name.
  final String assetName;

  /// Optional package name for package assets.
  final String? package;

  @override
  List<dynamic> toJson() {
    return <dynamic>[
      'fromAsset',
      assetName,
      if (package != null) package,
    ];
  }
}

/// Supported node types.
enum MarkerRenderNodeType {
  /// Container layout.
  container('container'),

  /// Horizontal layout.
  row('row'),

  /// Vertical layout.
  column('column'),

  /// Framed layout.
  stack('stack'),

  /// Text node.
  text('text'),

  /// Image node.
  image('image'),

  /// Empty space.
  space('space');

  const MarkerRenderNodeType(this.value);

  /// Platform-channel value.
  final String value;
}

/// Supported alignment values.
enum MarkerRenderAlignment {
  /// Center.
  center('center'),

  /// Top-left.
  topLeft('top|left'),

  /// Top-right.
  topRight('top|right'),

  /// Bottom-left.
  bottomLeft('bottom|left'),

  /// Bottom-right.
  bottomRight('bottom|right'),

  /// Top center.
  topCenter('top|center'),

  /// Bottom center.
  bottomCenter('bottom|center'),

  /// Center-left.
  centerLeft('center|left'),

  /// Center-right.
  centerRight('center|right');

  const MarkerRenderAlignment(this.value);

  /// Platform-channel value.
  final String value;
}

/// Supported text style values.
enum MarkerRenderTextStyleValue {
  /// Bold.
  bold('bold'),

  /// Italic.
  italic('italic'),

  /// Bold italic.
  boldItalic('boldItalic');

  const MarkerRenderTextStyleValue(this.value);

  /// Platform-channel value.
  final String value;
}

/// Supported font weight values.
enum MarkerRenderFontWeight {
  /// Bold.
  bold('bold'),

  /// Weight 700.
  w700('700'),

  /// Weight 800.
  w800('800'),

  /// Weight 900.
  w900('900');

  const MarkerRenderFontWeight(this.value);

  /// Platform-channel value.
  final String value;
}

/// Supported text overflow modes.
enum MarkerRenderEllipsize {
  /// Truncate at the start.
  start('start'),

  /// Truncate in the middle.
  middle('middle'),

  /// Truncate at the end.
  end('end');

  const MarkerRenderEllipsize(this.value);

  /// Platform-channel value.
  final String value;
}

String _colorToJson(Color color) {
  return '#${color.argbValue.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
