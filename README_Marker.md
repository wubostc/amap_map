# AMap Marker JSON Icon

This implementation lets Flutter/Dart send a declarative, typed marker icon tree to native platforms. Android renders it into a native `View` and passes it to `BitmapDescriptorFactory.fromView(view)`. iOS renders the same platform-neutral schema into a `UIImage`.

## Files

- `android/src/main/java/com/amap/flutter/map/overlays/marker/MarkerIconJsonRenderer.java`
  - Recursively renders `row`, `column`, `stack`, `text`, `image`, and `space`.
- `android/src/main/java/com/amap/flutter/map/overlays/marker/MarkerIconDescriptorFactory.java`
  - Converts rendered views into `BitmapDescriptor`.
- `ios/Classes/OverlayController/MarkerIcon/AMapMarkerIconJsonRenderer.m`
  - Recursively renders the same schema into a `UIImage`.
- `lib/src/types/amap_marker_icon_json.dart`
  - Dart-side typed helper API for building platform-neutral icon descriptions.

`BitmapDescriptor.fromJsonIcon` uses the normal marker `icon` field. Android handles the descriptor in `ConvertUtil`; iOS handles it in `AMapConvertUtil`.

## Dart usage

```dart
final iconJson = MarkerRender.icon(
  view: MarkerRender.container(
    style: const MarkerRenderContainerStyle(
      alignment: MarkerRenderAlignment.center,
    ),
    child: MarkerRender.column(
      style: const MarkerRenderColumnStyle(
        alignment: MarkerRenderAlignment.center,
      ),
      children: [
        MarkerRender.text(
          '12',
          style: const MarkerRenderTextStyle(
            textColor: Color(0xFFFFFFFF),
            textSize: 12,
            textStyle: MarkerRenderTextStyleValue.bold,
            backgroundColor: Color(0xFFE53935),
            radius: 10,
            padding: MarkerRenderInsets.fromLTRB(8, 2, 8, 2),
            alignment: MarkerRenderAlignment.center,
            includeFontPadding: false,
          ),
        ),
        MarkerRender.space(height: 2),
        MarkerRender.image(
          const MarkerRenderAssetSource('assets/marker_icon.png'),
          style: const MarkerRenderImageStyle(
            width: 48,
            height: 48,
          ),
        ),
      ],
    ),
  ),
);

final marker = Marker(
  position: const LatLng(31.2304, 121.4737),
  anchor: const Offset(0.5, 1.0),
  icon: BitmapDescriptor.fromJsonIcon(iconJson),
);
```

When the label changes, build a new icon JSON:

```dart
final updatedIconJson = MarkerRender.icon(
  view: MarkerRender.container(
    style: const MarkerRenderContainerStyle(
      alignment: MarkerRenderAlignment.center,
    ),
    child: MarkerRender.column(
      children: [
        MarkerRender.text(
          '18',
          style: const MarkerRenderTextStyle(
            textColor: Color(0xFFFFFFFF),
            textSize: 12,
            textStyle: MarkerRenderTextStyleValue.bold,
            backgroundColor: Color(0xFFE53935),
            radius: 10,
            padding: MarkerRenderInsets.fromLTRB(8, 2, 8, 2),
            alignment: MarkerRenderAlignment.center,
            includeFontPadding: false,
          ),
        ),
        MarkerRender.space(height: 2),
        MarkerRender.image(
          const MarkerRenderAssetSource('assets/marker_icon.png'),
          style: const MarkerRenderImageStyle(
            width: 48,
            height: 48,
          ),
        ),
      ],
    ),
  ),
);

final updatedMarker = marker.copyWith(
  iconParam: BitmapDescriptor.fromJsonIcon(updatedIconJson),
);
```

## JSON shape

```json
{
  "view": {
    "type": "container",
    "style": {
      "alignment": "center"
    },
    "child": {
      "type": "column",
      "children": [
        {
          "type": "text",
          "text": "12",
          "style": {
            "textColor": "#FFFFFFFF",
            "textSize": 12,
            "backgroundColor": "#FFE53935",
            "radius": 10,
            "padding": [8, 2, 8, 2],
            "alignment": "center"
          }
        },
        {
          "type": "image",
          "src": ["fromAsset", "assets/marker_icon.png"],
          "style": {
            "width": 48,
            "height": 48
          }
        }
      ]
    },
    "children": []
  }
}
```

## Supported view types

- `container`: Android `FrameLayout`; preferred root wrapper for fixed-size or wrap-content icons
- `row`: Android `LinearLayout` horizontal
- `column`: Android `LinearLayout` vertical
- `stack`: Android `FrameLayout`
- `text`: Android `TextView`
- `image`: Android `ImageView`
- `space`: Android `Space`

The root `view` only supports layout types: `container`, `row`, `column`, and `stack`. Leaf nodes (`text`, `image`, `space`) are only valid as children.

`container` only supports the singular `child` field and ignores `children`. `row`, `column`, and `stack` use `children` exclusively.

To add a new type later, add one `case` in `MarkerIconJsonRenderer.createView`, then read any new props from the node's root fields or from `props`.

## Style fields

All explicit dimensions are unitless numeric values. Omit `width` or `height` on `container`, `text`, and `space` to size from content. `stack` requires numeric `width` and `height`. Native renderers convert numeric values to platform display units.

The rendered ARGB bitmap is limited to 2 MiB after platform scaling. Icons over this limit render as an empty fallback icon.

Color values only support complete hexadecimal strings: `#RRGGBB` and `#AARRGGBB`. Color names such as `red` and `transparent` are not supported.

- `MarkerRenderContainerStyle`: `width`, `height`, `padding`, `margin`, `alignment`, `backgroundColor`, `radius`, `borderColor`, `borderWidth`
- `MarkerRenderRowStyle`: `margin`, `alignment`
- `MarkerRenderColumnStyle`: `margin`, `alignment`
- `MarkerRenderStackStyle`: required `width`, required `height`, `margin`, `alignment`
- `MarkerRenderTextStyle`: `width`, `height`, `padding`, `margin`, `alignment`, `backgroundColor`, `radius`, plus text fields below
- `MarkerRenderImageStyle`: fixed numeric `width`, fixed numeric `height`, `margin`

`alignment` is the Flutter-side high-level alignment field. Android maps it to native gravity and iOS maps it during its manual UIKit layout pass.

For `container`, `row`, `column`, and `stack`, `alignment` belongs to the parent and applies to every direct child. `row` and `column` keep children ordered on their main axis, so alignment controls their cross axis. Child margins participate in each child's alignment calculation.

Supported values are `center`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `topCenter`, `bottomCenter`, `centerLeft`, and `centerRight`.

Native style application is intentionally node-specific on both platforms:

- `container`: box background, border, radius, and padding
- `stack`: box background, border, and radius; padding is ignored
- `text`: box background, border, radius, and padding
- `row` and `column`: child alignment only
- `image` and `space`: size and margin only

## Text style fields

- `textColor`
- `textSize`: Android sp; iOS point size
- `textStyle`: `"bold"`, `"italic"`, or `"boldItalic"`
- `fontWeight`: `"bold"` or numeric strings like `"700"`
- `maxLines`, `minLines`, `singleLine`
- `ellipsize`: `"start"`, `"middle"`, or `"end"`
- `includeFontPadding`: Android `TextView` only. `false` removes Android's extra top and bottom font-metric padding; UIKit has no equivalent setting.

## Image source formats

- `["fromAsset", "assets/marker_icon.png"]`
- `["fromAsset", "assets/marker_icon.png", "package_name"]`

## Image style fields

Images require fixed numeric `width` and `height`. Native renderers convert those logical values to platform units and render the source as contain inside that fixed image box. Images do not inherit width or height from `row` or `column`.

## Native architecture

Both platforms consume the JSON shape produced by `MarkerRender`; no iOS-specific field names are added to Dart.

- Android: `ConvertUtil` validates `["fromJsonIcon", payload]`, `MarkerIconJsonRenderer` builds native `View` objects, and `MarkerIconDescriptorFactory` snapshots the root through `BitmapDescriptorFactory.fromView`.
- iOS: `AMapConvertUtil` validates `["fromJsonIcon", payload]` and invokes `AMapMarkerIconJsonRenderer`, which manually sizes and positions `UIView`, `UILabel`, `UIImageView`, and empty `UIView` nodes before rendering a `UIImage`.

This keeps Flutter as the platform-neutral schema owner while Android and iOS stay native renderers.

## Notes

- New Dart code should use the typed `MarkerRender` API. It serializes to the same JSON schema Android and iOS consume today.
- `BitmapDescriptor.fromJsonIcon` accepts `MarkerRenderIcon`, not a raw map, so callers stay on the typed schema.
- `BitmapDescriptorFactory.fromView(view)` snapshots the Android view. When the label changes, rebuild the icon JSON and update the marker through your marker icon update flow.
