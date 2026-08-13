import 'package:x_amap_base/x_amap_base.dart';

const double _latitudeTolerance = 0.0000001;

class RegionSnapshotRequest {
  RegionSnapshotRequest({
    required this.topLeft,
    required this.topRight,
    required this.width,
    required this.height,
    required this.timeout,
  }) {
    _validate();
  }

  final LatLng topLeft;
  final LatLng topRight;
  final int width;
  final int height;
  final Duration timeout;

  void _validate() {
    if (!topLeft.latitude.isFinite ||
        !topLeft.longitude.isFinite ||
        !topRight.latitude.isFinite ||
        !topRight.longitude.isFinite) {
      throw ArgumentError('区域截图坐标必须是有限数值');
    }
    if ((topLeft.latitude - topRight.latitude).abs() > _latitudeTolerance) {
      throw ArgumentError('topLeft 和 topRight 必须位于同一纬度');
    }
    if (topLeft.longitude >= topRight.longitude) {
      throw ArgumentError('topLeft 必须位于 topRight 左侧，暂不支持跨日期变更线');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('区域截图的 width 和 height 必须大于 0');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('区域截图的 timeout 必须大于 0');
    }
  }

  Map<String, Object> toMap() => <String, Object>{
        'topLeft': topLeft.toJson(),
        'topRight': topRight.toJson(),
        'width': width,
        'height': height,
        'timeoutMilliseconds': timeout.inMilliseconds,
      };
}
