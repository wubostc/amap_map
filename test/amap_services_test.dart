import 'package:amap_map2/amap_map2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel locationChannel = MethodChannel('amap_map2/location');
  const MethodChannel geocodingChannel = MethodChannel('amap_map2/geocoding');
  final List<MethodCall> locationCalls = <MethodCall>[];

  setUp(() {
    locationCalls.clear();
    AMapInitializer.updatePrivacyAgree(const AMapPrivacyStatement(
      hasContains: true,
      hasShow: true,
      hasAgree: true,
    ));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, (MethodCall call) async {
      locationCalls.add(call);
      if (call.method == 'location#getCurrent') {
        return <String, dynamic>{
          'provider': 'AMap',
          'latLng': <double>[39.9, 116.3],
          'accuracy': 5.0,
          'altitude': 10.0,
          'bearing': 20.0,
          'speed': 1.0,
          'time': 1234,
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geocodingChannel, null);
  });

  test('location options serialize and single location initializes SDK first',
      () async {
    final AMapLocation location =
        await AMapLocationClient.instance.getCurrentLocation(
      options: const AMapLocationOptions(
        accuracy: AMapLocationAccuracy.balanced,
        interval: Duration(seconds: 3),
        timeout: Duration(seconds: 8),
      ),
    );

    expect(locationCalls.map((MethodCall call) => call.method),
        <String>['services#initialize', 'location#getCurrent']);
    expect(locationCalls.last.arguments, <String, Object>{
      'accuracy': 'balanced',
      'interval': 3000,
      'timeout': 8000,
    });
    expect(location.latLng.latitude, 39.9);
    expect(location.latLng.longitude, closeTo(116.3, 1e-12));
    expect(location.accuracy, 5.0);
  });

  test('geocode trims input and converts native results', () async {
    MethodCall? geocodeCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geocodingChannel, (MethodCall call) async {
      geocodeCall = call;
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'location': <double>[39.90374, 116.397827],
          'formattedAddress': '北京市东城区天安门广场',
          'province': '北京市',
          'city': '北京市',
          'district': '东城区',
          'adCode': '110101',
        },
      ];
    });

    final List<AMapGeocodeResult> results =
        await AMapGeocodingClient.instance.geocode(
      address: '  天安门广场  ',
      city: ' 北京 ',
    );

    expect(geocodeCall?.method, 'geocoding#geocode');
    expect(geocodeCall?.arguments,
        <String, dynamic>{'address': '天安门广场', 'city': '北京'});
    expect(results, hasLength(1));
    expect(results.single.formattedAddress, '北京市东城区天安门广场');
    expect(results.single.location.longitude, closeTo(116.397827, 1e-12));
    expect(results.single.adCode, '110101');
  });

  test('geocode rejects an empty address before invoking native code', () {
    expect(
      () => AMapGeocodingClient.instance.geocode(address: '   '),
      throwsArgumentError,
    );
  });

  test('reverse geocode returns a display name for the selected point',
      () async {
    MethodCall? reverseCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geocodingChannel, (MethodCall call) async {
      reverseCall = call;
      return <String, dynamic>{
        'location': <double>[39.90374, 116.397827],
        'formattedAddress': '北京市东城区东长安街天安门',
        'placeName': '天安门',
        'street': '东长安街',
        'number': '1号',
        'adCode': '110101',
      };
    });

    final AMapReverseGeocodeResult result =
        await AMapGeocodingClient.instance.reverseGeocode(
      location: const LatLng(39.90374, 116.397827),
      radius: 500,
    );

    expect(reverseCall?.method, 'geocoding#reverseGeocode');
    expect((reverseCall?.arguments as Map<dynamic, dynamic>)['radius'], 500);
    expect(result.displayName, '天安门');
    expect(result.formattedAddress, '北京市东城区东长安街天安门');
    expect(result.street, '东长安街');
    expect(result.location.longitude, closeTo(116.397827, 1e-12));
  });

  test('reverse geocode validates the SDK radius range', () {
    expect(
      () => AMapGeocodingClient.instance.reverseGeocode(
        location: const LatLng(39.9, 116.3),
        radius: 3001,
      ),
      throwsArgumentError,
    );
  });

  test('revoking privacy agreement is synchronized to native services',
      () async {
    const AMapPrivacyStatement revoked = AMapPrivacyStatement(
      hasContains: true,
      hasShow: true,
      hasAgree: false,
    );

    AMapInitializer.updatePrivacyAgree(revoked);
    await Future<void>.delayed(Duration.zero);

    expect(locationCalls, hasLength(1));
    expect(locationCalls.single.method, 'services#updatePrivacy');
    expect(locationCalls.single.arguments, revoked.toMap());
  });
}
