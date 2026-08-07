# amap_map

[![pub package](https://img.shields.io/pub/v/amap_map.svg)](https://pub.dev/packages/amap_map)

基于[高德开放平台地图 SDK](https://lbs.amap.com/api/)的 Flutter 地图插件，支持 Android 和 iOS。

|             | Android                                  | iOS      |
| ----------- | ---------------------------------------- | -------- |
| **AMapSDK** | 11.2.000_loc11.2.000_sea9.8.0             | 11.2.000 |
| **Support** | minSdk 21+                               | 12.0+    |

## 功能

- 显示高德 3D 地图
- 地图类型、路况、建筑物、文字标注、语言、Logo、手势等配置
- 地图点击、长按、POI 点击、相机移动、定位回调
- Marker、Polyline、Polygon 覆盖物
- Marker 点击、拖拽、自定义图标、自定义 InfoWindow
- Polyline 点击、纹理、虚线、线头、连接点样式
- Polygon 点击、边框、填充、显隐、点集更新
- 运行时通过 `AMapController` 动态增删改覆盖物
- 经纬度和屏幕坐标互转、截图、清理缓存

## 安装

```bash
flutter pub add amap_map
```

需要同时引入 `x_amap_base` 中的基础类型：

```dart
import 'package:amap_map/amap_map.dart';
import 'package:x_amap_base/x_amap_base.dart';
```

## 准备工作

登录[高德开放平台](https://lbs.amap.com/)申请 Key：

- [Android 获取 Key](https://lbs.amap.com/api/android-sdk/guide/create-project/get-key)
- [iOS 获取 Key](https://lbs.amap.com/api/ios-sdk/guide/create-project/get-key)

高德 SDK 需要先完成隐私合规授权。建议在展示 `AMapWidget` 前调用：

```dart
class ConstConfig {
  static const AMapApiKey amapApiKeys = AMapApiKey(
    androidKey: '你的 Android Key',
    iosKey: '你的 iOS Key',
  );

  static const AMapPrivacyStatement amapPrivacyStatement =
      AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );
}
```

```dart
@override
Widget build(BuildContext context) {
  AMapInitializer.init(context, apiKey: ConstConfig.amapApiKeys);
  AMapInitializer.updatePrivacyAgree(ConstConfig.amapPrivacyStatement);

  return const MaterialApp(home: MapPage());
}
```

高德 SDK 合规方案请参考：[高德开放平台合规使用说明](https://lbs.amap.com/news/sdkhgsy)。

## 基础地图

```dart
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  AMapController? _controller;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(39.909187, 116.397451),
    zoom: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AMapWidget(
        initialCameraPosition: _initialPosition,
        trafficEnabled: false,
        buildingsEnabled: true,
        labelsEnabled: true,
        onMapCreated: (AMapController controller) {
          _controller = controller;
        },
        onTap: (LatLng position) {
          debugPrint('map tapped: $position');
        },
        onLongPress: (LatLng position) {
          debugPrint('map long pressed: $position');
        },
      ),
    );
  }
}
```

## 地图配置

常用配置可以直接传给 `AMapWidget`：

```dart
AMapWidget(
  initialCameraPosition: const CameraPosition(
    target: LatLng(39.909187, 116.397451),
    zoom: 12,
  ),
  mapType: MapType.normal,
  trafficEnabled: false,
  buildingsEnabled: true,
  labelsEnabled: true,
  compassEnabled: true,
  scaleEnabled: true,
  touchPoiEnabled: true,
  zoomGesturesEnabled: true,
  scrollGesturesEnabled: true,
  rotateGesturesEnabled: true,
  tiltGesturesEnabled: true,
  mapLanguage: MapLanguage.chinese,
)
```

支持的地图类型：

- `MapType.normal`
- `MapType.satellite`
- `MapType.night`
- `MapType.navi`
- `MapType.bus`

### 自定义地图样式

从高德开放平台下载自定义地图样式文件后，可以传入 `style.data` 和 `style_extra.data`：

```dart
final ByteData styleData = await rootBundle.load('assets/style.data');
final ByteData styleExtraData = await rootBundle.load('assets/style_extra.data');

final CustomStyleOptions customStyleOptions = CustomStyleOptions(
  true,
  styleData: styleData.buffer.asUint8List(),
  styleExtraData: styleExtraData.buffer.asUint8List(),
);
```

```dart
AMapWidget(
  customStyleOptions: customStyleOptions,
)
```

## Marker

```dart
final Marker marker = Marker(
  position: const LatLng(39.909187, 116.397451),
  infoWindow: const InfoWindow(
    title: '天安门',
    snippet: '北京市东城区',
  ),
  onTap: (String markerId) {
    debugPrint('marker tapped: $markerId');
  },
);
```

```dart
AMapWidget(
  markers: <Marker>{marker},
)
```

Marker 支持：

- `position`
- `icon`
- `alpha`
- `anchor`
- `clickable`
- `draggable`
- `infoWindow`
- `infoWindowEnable`
- `rotation`
- `visible`
- `zIndex`
- `onTap`
- `onDragEnd`

### 声明式 JSON Marker 图标

`BitmapDescriptor.fromJsonIcon` 支持用一棵声明式、强类型的 Dart 节点树描述 Marker 图标。Flutter/Dart 将平台无关的图标结构传给原生侧：

- Android 渲染为原生 `View`，再通过 `BitmapDescriptorFactory.fromView(view)` 生成 Marker 图标。
- iOS 用同一份 JSON schema 渲染为 `UIImage`。

相关文件：

- `lib/src/types/amap_marker_icon_json.dart`：Dart 侧强类型构建 API。
- `android/src/main/java/com/amap/flutter/map/overlays/marker/MarkerIconJsonRenderer.java`：Android 递归渲染 `row`、`column`、`stack`、`text`、`image`、`space`。
- `android/src/main/java/com/amap/flutter/map/overlays/marker/MarkerIconDescriptorFactory.java`：把原生 View 转为 `BitmapDescriptor`。
- `ios/Classes/OverlayController/MarkerIcon/AMapMarkerIconJsonRenderer.m`：iOS 递归渲染同一份 schema 到 `UIImage`。

`BitmapDescriptor.fromJsonIcon` 使用普通 Marker 的 `icon` 字段。Android 在 `ConvertUtil` 中处理 descriptor，iOS 在 `AMapConvertUtil` 中处理 descriptor。

#### Dart 用法

```dart
final MarkerRenderIcon iconJson = MarkerRender.icon(
  view: MarkerRender.container(
    style: const MarkerRenderContainerStyle(
      alignment: MarkerRenderAlignment.center,
    ),
    child: MarkerRender.column(
      style: const MarkerRenderColumnStyle(
        alignment: MarkerRenderAlignment.center,
      ),
      children: <MarkerRenderNode>[
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

final Marker marker = Marker(
  position: const LatLng(31.2304, 121.4737),
  anchor: const Offset(0.5, 1.0),
  icon: BitmapDescriptor.fromJsonIcon(iconJson),
);
```

当标签变化时，重新构建图标 JSON 并更新 Marker：

```dart
final MarkerRenderIcon updatedIconJson = MarkerRender.icon(
  view: MarkerRender.container(
    style: const MarkerRenderContainerStyle(
      alignment: MarkerRenderAlignment.center,
    ),
    child: MarkerRender.column(
      children: <MarkerRenderNode>[
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

final Marker updatedMarker = marker.copyWith(
  icon: BitmapDescriptor.fromJsonIcon(updatedIconJson),
);
```

#### JSON 结构

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
    }
  }
}
```

#### 支持的节点类型

- `container`：Android `FrameLayout`；适合作为固定尺寸或 wrap-content 的根包装节点。
- `row`：Android `LinearLayout` horizontal。
- `column`：Android `LinearLayout` vertical。
- `stack`：Android `FrameLayout`。
- `text`：Android `TextView`。
- `image`：Android `ImageView`。
- `space`：Android `Space`。

根 `view` 只支持布局类型：`container`、`row`、`column`、`stack`。叶子节点 `text`、`image`、`space` 只能作为子节点。

`container` 只支持单个 `child` 字段，会忽略 `children`。`row`、`column`、`stack` 使用 `children`。

后续增加新节点类型时，需要在 `MarkerIconJsonRenderer.createView` 中新增一个 `case`，并从节点根字段或 `props` 中读取新增属性。

#### 样式字段

所有显式尺寸都是无单位数字。原生渲染器会把数值转换为平台显示单位。

`container`、`text`、`space` 可以省略 `width` 或 `height`，从内容自动计算尺寸。`stack` 必须提供固定 `width` 和 `height`。图片必须提供固定 `width` 和 `height`。

渲染后的 ARGB bitmap 在平台缩放后限制为 2 MiB，超过限制会使用空白 fallback 图标。

颜色只支持完整十六进制字符串：

- `#RRGGBB`
- `#AARRGGBB`

不支持 `red`、`transparent` 这类颜色名。

支持的 style 类型：

- `MarkerRenderContainerStyle`：`width`、`height`、`padding`、`margin`、`alignment`、`backgroundColor`、`radius`、`borderColor`、`borderWidth`
- `MarkerRenderRowStyle`：`margin`、`alignment`
- `MarkerRenderColumnStyle`：`margin`、`alignment`
- `MarkerRenderStackStyle`：必填 `width`、必填 `height`、`margin`、`alignment`
- `MarkerRenderTextStyle`：`width`、`height`、`padding`、`margin`、`alignment`、`backgroundColor`、`radius`，以及文本样式字段
- `MarkerRenderImageStyle`：固定 `width`、固定 `height`、`margin`

`alignment` 是 Flutter 侧的高级对齐字段。Android 映射为原生 gravity，iOS 在手动 UIKit 布局阶段映射。

对于 `container`、`row`、`column`、`stack`，`alignment` 属于父节点，作用于直接子节点。`row` 和 `column` 保持主轴顺序，`alignment` 控制交叉轴。子节点的 `margin` 会参与对齐计算。

支持的对齐值：

- `center`
- `topLeft`
- `topRight`
- `bottomLeft`
- `bottomRight`
- `topCenter`
- `bottomCenter`
- `centerLeft`
- `centerRight`

原生样式应用是节点专属的：

- `container`：背景、边框、圆角、padding
- `stack`：背景、边框、圆角；忽略 padding
- `text`：背景、边框、圆角、padding
- `row` / `column`：子节点对齐
- `image` / `space`：尺寸和 margin

#### 文本样式字段

- `textColor`
- `textSize`：Android 为 sp，iOS 为 point size
- `textStyle`：`bold`、`italic`、`boldItalic`
- `fontWeight`：`bold` 或 `"700"` 这类数值字符串
- `maxLines`
- `minLines`
- `singleLine`
- `ellipsize`：`start`、`middle`、`end`
- `includeFontPadding`：仅 Android `TextView` 生效；`false` 会移除 Android 额外字体上下 padding，UIKit 无等价设置

#### 图片源格式

```json
["fromAsset", "assets/marker_icon.png"]
```

```json
["fromAsset", "assets/marker_icon.png", "package_name"]
```

图片以 contain 方式渲染到固定尺寸图片盒中，不会从 `row` 或 `column` 继承宽高。

#### 原生架构

两端都消费 `MarkerRender` 生成的同一份 JSON：

- Android：`ConvertUtil` 校验 `["fromJsonIcon", payload]`，`MarkerIconJsonRenderer` 构建原生 `View`，`MarkerIconDescriptorFactory` 通过 `BitmapDescriptorFactory.fromView` 截图。
- iOS：`AMapConvertUtil` 校验 `["fromJsonIcon", payload]`，`AMapMarkerIconJsonRenderer` 手动布局 `UIView`、`UILabel`、`UIImageView` 和空 `UIView`，最终渲染成 `UIImage`。

这样 Flutter 负责平台无关 schema，Android 和 iOS 保持原生渲染。

#### 注意事项

- 新 Dart 代码建议使用强类型 `MarkerRender` API，不建议手写 raw map。
- `BitmapDescriptor.fromJsonIcon` 接收 `MarkerRenderIcon`。
- Android 的 `BitmapDescriptorFactory.fromView(view)` 是快照机制。标签变化时，需要重新构建 icon JSON 并更新 Marker。

## Polyline

```dart
final Polyline polyline = Polyline(
  points: const <LatLng>[
    LatLng(39.938698, 116.275177),
    LatLng(39.966069, 116.289253),
    LatLng(39.944226, 116.306076),
  ],
  width: 8,
  color: const Color(0xFF1677FF),
  onTap: (String polylineId) {
    debugPrint('polyline tapped: $polylineId');
  },
);
```

```dart
AMapWidget(
  polylines: <Polyline>{polyline},
)
```

如果线太细导致难点击，可以额外叠加一条更宽、几乎透明的 Polyline 作为点击热区。

## Polygon

```dart
final Polygon polygon = Polygon(
  points: const <LatLng>[
    LatLng(39.835334, 116.3710069),
    LatLng(39.843082, 116.3709830),
    LatLng(39.845932, 116.3642213),
    LatLng(39.841562, 116.3455680),
  ],
  strokeWidth: 4,
  strokeColor: const Color(0xFF1677FF),
  fillColor: const Color(0x331677FF),
  onTap: (String polygonId) {
    debugPrint('polygon tapped: $polygonId');
  },
);
```

```dart
AMapWidget(
  polygons: <Polygon>{polygon},
)
```

`Polygon.onTap` 在 Flutter 层实现：地图点击后使用 `turf.booleanPointInPolygon` 判断点击点是否落在 Polygon 内。高德国内地图默认使用 GCJ-02，只要点击点和 Polygon 点集使用同一坐标系即可。多个 Polygon 重叠时，后添加的 Polygon 优先响应。

## 动态更新覆盖物

通过 `AMapController` 可以在地图创建后动态增删改覆盖物：

```dart
AMapController? controller;

AMapWidget(
  onMapCreated: (AMapController value) {
    controller = value;
  },
)
```

```dart
await controller?.setMarker(marker);
await controller?.removeMarker(marker.id);

await controller?.setPolyline(polyline);
await controller?.removePolyline(polyline.id);

await controller?.setPolygon(polygon);
await controller?.removePolygon(polygon.id);
```

## 控制地图

```dart
await controller?.moveCamera(
  CameraUpdate.newLatLngZoom(
    const LatLng(39.909187, 116.397451),
    15,
  ),
);

final Uint8List? image = await controller?.takeSnapshot();

final ScreenCoordinate screen =
    await controller!.toScreenCoordinate(const LatLng(39.909187, 116.397451));

final LatLng position = await controller!.fromScreenCoordinate(screen);
```

常用控制器 API：

- `moveCamera`
- `takeSnapshot`
- `clearDisk`
- `toScreenCoordinate`
- `fromScreenCoordinate`
- `setMapOptions`
- `setMarker` / `removeMarker`
- `setPolyline` / `removePolyline`
- `setPolygon` / `removePolygon`
- `getMapContentApprovalNumber`
- `getSatelliteImageApprovalNumber`

## 自定义 InfoWindow

可以通过 `infoWindowAdapter` 自定义 Marker 的气泡 Widget：

```dart
AMapWidget(
  markers: markers,
  infoWindowAdapter: InfoWindowAdapter(
    getInfoWindow: (BuildContext context, Marker marker) {
      return Positioned(
        left: 16,
        top: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(marker.infoWindow.title ?? ''),
          ),
        ),
      );
    },
  ),
)
```

## 坐标系说明

高德国内地图使用 GCJ-02 坐标系。地图点击回调、Marker、Polyline、Polygon 的坐标应保持同一坐标系。不要混用 WGS84、GCJ-02、BD-09，否则覆盖物位置和点击判断会出现偏移。

## 常见问题

### Android targetSdkVersion >= 30 返回地图页闪退

可以在 Android `AndroidManifest.xml` 的 `application` 中增加：

```xml
<application android:allowNativeHeapPointerTagging="false">
  ...
</application>
```

参考：[Android tagged pointers](https://source.android.com/devices/tech/debug/tagged-pointers)。

### 模拟器 OpenGL 崩溃

如果模拟器运行遇到类似：

```text
com.amap.api.col.3sl.dl$b.createContext(GlesUtility.java:73)
```

可尝试将模拟器图像加速模式切换为 `Software`。

## 示例

完整示例请查看 [`example`](example) 目录。

## License

[Apache License 2.0](LICENSE)
