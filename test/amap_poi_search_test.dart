import 'package:amap_map2/amap_map2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel locationChannel = MethodChannel('amap_map2/location');
  const MethodChannel poiChannel = MethodChannel('amap_map2/poi_search');
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
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(poiChannel, null);
  });

  test('keyword search serializes common options and parses POIs', () async {
    MethodCall? searchCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(poiChannel, (MethodCall call) async {
      searchCall = call;
      return <String, dynamic>{
        'totalCount': 1,
        'page': 2,
        'pageSize': 10,
        'pois': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'B0FF',
            'name': '天安门',
            'location': <double>[39.90374, 116.397827],
            'type': '风景名胜',
            'typeCode': '110000',
            'businessArea': '天安门',
            'rating': 4.8,
            'photos': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': '正面',
                'url': 'https://example/photo',
              },
            ],
          },
        ],
      };
    });

    final AMapPoiSearchResult result =
        await AMapPoiSearchClient.instance.searchKeyword(
      keyword: '天安门',
      location: const LatLng(39.9, 116.3),
      options: const AMapPoiSearchOptions(
        types: '风景名胜|公园',
        city: '北京',
        cityLimit: true,
        page: 2,
        pageSize: 10,
        distanceSort: true,
        showFields: <AMapPoiSearchField>{
          AMapPoiSearchField.business,
          AMapPoiSearchField.photos,
        },
        premium: AMapPoiSearchPremium.entirety,
        customParams: <String, String>{'trace': 'test'},
      ),
    );

    expect(locationCalls.map((MethodCall call) => call.method),
        <String>['services#initialize']);
    expect(searchCall?.method, 'poiSearch#search');
    final Map<dynamic, dynamic> arguments =
        searchCall!.arguments as Map<dynamic, dynamic>;
    expect(arguments['mode'], 'keyword');
    expect(arguments['keyword'], '天安门');
    expect(arguments['types'], '风景名胜|公园');
    expect(arguments['cityLimit'], true);
    expect(arguments['page'], 2);
    expect(arguments['pageSize'], 10);
    expect(arguments['queryLanguage'], 'zh-CN');
    expect(arguments['showFields'], (1 << 2) | (1 << 5));
    expect(arguments['premium'], 'entirety');
    expect(arguments['customParams'], <String, String>{'trace': 'test'});
    expect(result.totalCount, 1);
    expect(result.page, 2);
    expect(result.pois.single.name, '天安门');
    expect(result.pois.single.rating, '4.8');
    expect(result.pois.single.photos.single.url, 'https://example/photo');
    expect(result.pois.single.distance, isNull);
  });

  test('reads native around distance without recalculating in Dart', () {
    final AMapPoiSearchResult result = AMapPoiSearchResult.fromMap(
      <String, dynamic>{
        'pois': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'B0FF',
            'name': '天安门',
            'location': <double>[39.90374, 116.397827],
            'distance': 123.5,
          },
        ],
      },
    );
    expect(result.pois.single.distance, 123.5);
  });

  test('query and radius validation happen before the native call', () async {
    Future<void> expectArgumentError(Future<Object?> future) async {
      await expectLater(future, throwsA(isA<ArgumentError>()));
    }

    await expectArgumentError(
      AMapPoiSearchClient.instance.searchAround(
        location: const LatLng(39.9, 116.3),
        radius: 0,
        keyword: null,
      ),
    );
    await expectArgumentError(
      AMapPoiSearchClient.instance.searchAround(
        location: const LatLng(39.9, 116.3),
        radius: 50001,
      ),
    );
    await expectArgumentError(
      AMapPoiSearchClient.instance.searchAround(
        location: const LatLng(39.9, 116.3),
      ),
    );
    await expectArgumentError(
      AMapPoiSearchClient.instance.searchKeyword(
        keyword: '咖啡店',
        options: const AMapPoiSearchOptions(cityLimit: true),
      ),
    );
  });

  test('normalizes optional text before native call', () async {
    MethodCall? searchCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(poiChannel, (MethodCall call) async {
      searchCall = call;
      return <String, dynamic>{
        'totalCount': 0,
        'page': 1,
        'pageSize': 20,
        'pois': <Map<String, dynamic>>[],
      };
    });

    await AMapPoiSearchClient.instance.searchKeyword(
      keyword: '  餐厅  ',
      location: const LatLng(39.9, 116.3),
      options: const AMapPoiSearchOptions(
        types: ' 050000 ',
        city: ' 北京 ',
        building: ' B0FF ',
        channel: ' web ',
      ),
    );

    final Map<dynamic, dynamic> arguments =
        searchCall!.arguments as Map<dynamic, dynamic>;
    expect(arguments['keyword'], '餐厅');
    expect(arguments['types'], '050000');
    expect(arguments['city'], '北京');
    expect(arguments['building'], 'B0FF');
    expect(arguments['channel'], 'web');
    expect(arguments.containsKey('polygon'), isFalse);
  });

  test('supports type-only keyword queries and ignores cityLimit around',
      () async {
    final List<MethodCall> searchCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(poiChannel, (MethodCall call) async {
      searchCalls.add(call);
      return <String, dynamic>{
        'totalCount': 0,
        'page': 1,
        'pageSize': 20,
        'pois': <Map<String, dynamic>>[],
      };
    });

    await AMapPoiSearchClient.instance.searchKeyword(
      options: const AMapPoiSearchOptions(types: '050000'),
    );
    await AMapPoiSearchClient.instance.searchAround(
      location: const LatLng(39.9, 116.3),
      keyword: '咖啡店',
      options: const AMapPoiSearchOptions(
        city: '北京',
        cityLimit: true,
      ),
    );

    final Map<dynamic, dynamic> keywordArguments =
        searchCalls[0].arguments as Map<dynamic, dynamic>;
    expect(keywordArguments.containsKey('keyword'), isFalse);
    expect(keywordArguments['types'], '050000');
    expect(keywordArguments['cityLimit'], false);

    final Map<dynamic, dynamic> aroundArguments =
        searchCalls[1].arguments as Map<dynamic, dynamic>;
    expect(aroundArguments['mode'], 'around');
    expect(aroundArguments['cityLimit'], false);
  });
}
