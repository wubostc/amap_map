import 'package:amap_map2/src/core/method_channel_amap_map2.dart';
import 'package:amap_map2/src/core/region_snapshot_request.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serializes a valid region snapshot request', () {
    final RegionSnapshotRequest request = RegionSnapshotRequest(
      topLeft: const LatLng(39.95, 116.30),
      topRight: const LatLng(39.95, 116.50),
      width: 1200,
      height: 800,
      timeout: const Duration(seconds: 12),
    );

    final Map<String, Object> map = request.toMap();
    expect((map['topLeft']! as List<double>)[0], closeTo(39.95, 1e-12));
    expect((map['topLeft']! as List<double>)[1], closeTo(116.30, 1e-12));
    expect((map['topRight']! as List<double>)[0], closeTo(39.95, 1e-12));
    expect((map['topRight']! as List<double>)[1], closeTo(116.50, 1e-12));
    expect(map, containsPair('width', 1200));
    expect(map, containsPair('height', 800));
    expect(map, containsPair('timeoutMilliseconds', 12000));
  });

  test('rejects points that do not define a horizontal upper edge', () {
    expect(
      () => RegionSnapshotRequest(
        topLeft: const LatLng(39.95, 116.30),
        topRight: const LatLng(39.94, 116.50),
        width: 800,
        height: 600,
        timeout: const Duration(seconds: 30),
      ),
      throwsArgumentError,
    );
  });

  test('rejects an inverted or dateline-crossing longitude range', () {
    expect(
      () => RegionSnapshotRequest(
        topLeft: const LatLng(39.95, 116.50),
        topRight: const LatLng(39.95, 116.30),
        width: 800,
        height: 600,
        timeout: const Duration(seconds: 30),
      ),
      throwsArgumentError,
    );
  });

  test('rejects non-positive dimensions and timeout', () {
    RegionSnapshotRequest create({
      int width = 800,
      int height = 600,
      Duration timeout = const Duration(seconds: 30),
    }) =>
        RegionSnapshotRequest(
          topLeft: const LatLng(39.95, 116.30),
          topRight: const LatLng(39.95, 116.50),
          width: width,
          height: height,
          timeout: timeout,
        );

    expect(() => create(width: 0), throwsArgumentError);
    expect(() => create(timeout: Duration.zero), throwsArgumentError);
  });

  test('allows requests larger than 16 million pixels', () {
    final RegionSnapshotRequest request = RegionSnapshotRequest(
      topLeft: const LatLng(39.95, 116.30),
      topRight: const LatLng(39.95, 116.50),
      width: 8000,
      height: 8000,
      timeout: const Duration(seconds: 30),
    );

    expect(request.toMap(), containsPair('width', 8000));
    expect(request.toMap(), containsPair('height', 8000));
  });

  test('sends the request through the map method channel', () async {
    const int mapId = 73;
    const MethodChannel channel = MethodChannel('amap_map2_$mapId');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'map#takeRegionSnapshot') {
        return Uint8List.fromList(<int>[137, 80, 78, 71]);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final MethodChannelAMapFlutterMap platform = MethodChannelAMapFlutterMap();
    await platform.init(mapId);
    final Uint8List bytes = await platform.takeRegionSnapshot(
      mapId: mapId,
      request: RegionSnapshotRequest(
        topLeft: const LatLng(39.95, 116.30),
        topRight: const LatLng(39.95, 116.50),
        width: 1200,
        height: 800,
        timeout: const Duration(seconds: 12),
      ),
    );

    expect(bytes, <int>[137, 80, 78, 71]);
    expect(calls.last.method, 'map#takeRegionSnapshot');
    final Map<Object?, Object?> arguments =
        calls.last.arguments as Map<Object?, Object?>;
    expect(arguments['width'], 1200);
    expect(arguments['height'], 800);
    expect(arguments['timeoutMilliseconds'], 12000);
    expect(
      (arguments['topLeft']! as List<Object?>)[1] as double,
      closeTo(116.30, 1e-12),
    );
  });
}
