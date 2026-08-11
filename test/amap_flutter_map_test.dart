import 'package:amap_map2/amap_map2.dart';
import 'package:amap_map2/src/utils/polygon_hit_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_amap_base/x_amap_base.dart';

void main() {
  // const MethodChannel channel = MethodChannel('amap_map2');

  TestWidgetsFlutterBinding.ensureInitialized();

  test('AMapOptions serializes defined values without null fields', () {
    final AMapOptions options = AMapOptions(
      mapType: MapType.satellite,
      buildingsEnabled: false,
      customStyleOptions: CustomStyleOptions(true),
      compassEnabled: false,
      minMaxZoomPreference: const MinMaxZoomPreference(4, 18),
      trafficEnabled: false,
      myLocationStyleOptions: MyLocationStyleOptions(false),
      logoPosition: 2,
      logoBottomMargin: 3,
      logoLeftMargin: 4,
      mapLanguage: MapLanguage.english,
    );

    expect(options.toMap(), <String, dynamic>{
      'mapType': MapType.satellite.index,
      'buildingsEnabled': false,
      'customStyleOptions': <String, dynamic>{'enabled': true},
      'compassEnabled': false,
      'minMaxZoomPreference': <double>[4, 18],
      'trafficEnabled': false,
      'myLocationStyle': <String, dynamic>{'enabled': false},
      'logoPosition': 2,
      'logoBottomMargin': 3,
      'logoLeftMargin': 4,
      'mapLanguage': 'en',
    });
  });

  test('Marker infoWindowEnable defaults to false', () {
    final Marker marker = Marker(
      position: const LatLng(39.909187, 116.397451),
      infoWindow: const InfoWindow(title: '天安门'),
    );

    expect(marker.infoWindowEnable, isFalse);
    expect(marker.toMap()['infoWindowEnable'], isFalse);

    final Marker enabledMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
      infoWindowEnable: true,
      infoWindow: const InfoWindow(title: '天安门'),
    );

    expect(enabledMarker.infoWindowEnable, isTrue);
    expect(enabledMarker.toMap()['infoWindowEnable'], isTrue);
  });

  test('Marker copyWith preserves drag callbacks', () {
    final List<String> eventIds = <String>[];
    final List<LatLng> eventPositions = <LatLng>[];
    final Marker marker = Marker(
      position: const LatLng(39.909187, 116.397451),
      onDragStart: (String markerId, LatLng position) {
        eventIds.add('start:$markerId');
        eventPositions.add(position);
      },
      onDrag: (String markerId, LatLng position) {
        eventIds.add('drag:$markerId');
        eventPositions.add(position);
      },
      onDragEnd: (String markerId, LatLng position) {
        eventIds.add('end:$markerId');
        eventPositions.add(position);
      },
    );

    final Marker copy = marker.copyWith(alpha: 0.5);
    copy.onDragStart?.call(copy.id, const LatLng(1, 2));
    copy.onDrag?.call(copy.id, const LatLng(3, 4));
    copy.onDragEnd?.call(copy.id, const LatLng(5, 6));

    expect(copy.onDragStart, same(marker.onDragStart));
    expect(copy.onDrag, same(marker.onDrag));
    expect(copy.onDragEnd, same(marker.onDragEnd));
    expect(eventIds, <String>[
      'start:${marker.id}',
      'drag:${marker.id}',
      'end:${marker.id}',
    ]);
    expect(eventPositions, <LatLng>[
      const LatLng(1, 2),
      const LatLng(3, 4),
      const LatLng(5, 6),
    ]);
  });

  test('Marker only serializes a non-default dragging event frequency', () {
    final Marker defaultMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
    );
    final Marker customMarker = defaultMarker.copyWith(
      draggingEventFrequency: 20,
    );

    expect(defaultMarker.draggingEventFrequency, 30);
    expect(defaultMarker.toMap(), isNot(contains('draggingEventFrequency')));
    expect(customMarker.draggingEventFrequency, 20);
    expect(customMarker.toMap()['draggingEventFrequency'], 20);
  });

  test('Marker clamps dragging event frequency to the supported range', () {
    final Marker lowFrequencyMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 0,
    );
    final Marker highFrequencyMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 121,
    );

    expect(lowFrequencyMarker.draggingEventFrequency, 1);
    expect(highFrequencyMarker.draggingEventFrequency, 120);
    expect(lowFrequencyMarker.toMap()['draggingEventFrequency'], 1);
    expect(highFrequencyMarker.toMap()['draggingEventFrequency'], 120);
  });

  test('Marker accepts and serializes dragging event frequency boundaries', () {
    final Marker minimumFrequencyMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 1,
    );
    final Marker maximumFrequencyMarker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 120,
    );

    expect(minimumFrequencyMarker.draggingEventFrequency, 1);
    expect(minimumFrequencyMarker.toMap()['draggingEventFrequency'], 1);
    expect(maximumFrequencyMarker.draggingEventFrequency, 120);
    expect(maximumFrequencyMarker.toMap()['draggingEventFrequency'], 120);
  });

  test('Marker copyWith and clone preserve dragging event frequency', () {
    final Marker marker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 60,
    );

    final Marker copy = marker.copyWith(alpha: 0.5);
    final Marker clone = marker.clone();
    final Marker resetToDefault = marker.copyWith(
      draggingEventFrequency: Marker.defaultDraggingEventFrequency,
    );

    expect(copy.id, marker.id);
    expect(copy.draggingEventFrequency, 60);
    expect(copy.toMap()['draggingEventFrequency'], 60);
    expect(clone.id, marker.id);
    expect(clone.draggingEventFrequency, 60);
    expect(clone.toMap()['draggingEventFrequency'], 60);
    expect(
      resetToDefault.draggingEventFrequency,
      Marker.defaultDraggingEventFrequency,
    );
    expect(
      resetToDefault.toMap(),
      isNot(contains('draggingEventFrequency')),
    );
  });

  test('Marker equality and hashCode include dragging event frequency', () {
    final Marker marker = Marker(
      position: const LatLng(39.909187, 116.397451),
      draggingEventFrequency: 60,
    );
    final Marker sameFrequency = marker.copyWith();
    final Marker differentFrequency = marker.copyWith(
      draggingEventFrequency: 20,
    );

    expect(sameFrequency, marker);
    expect(sameFrequency.hashCode, marker.hashCode);
    expect(differentFrequency, isNot(marker));
  });

  test('Polygon defensively copies points', () {
    final List<LatLng> points = <LatLng>[
      const LatLng(39.0, 116.0),
      const LatLng(40.0, 117.0),
    ];
    final Polygon polygon = Polygon(points: points);

    points.add(const LatLng(41.0, 118.0));

    expect(polygon.points, hasLength(2));

    final Polygon clone = polygon.clone();
    polygon.points.add(const LatLng(42.0, 119.0));

    expect(clone.points, hasLength(2));
  });

  test('Polyline defensively copies points', () {
    final List<LatLng> points = <LatLng>[
      const LatLng(39.0, 116.0),
      const LatLng(40.0, 117.0),
    ];
    final Polyline polyline = Polyline(points: points);

    points.add(const LatLng(41.0, 118.0));

    expect(polyline.points, hasLength(2));

    final Polyline clone = polyline.clone();
    polyline.points.add(const LatLng(42.0, 119.0));

    expect(clone.points, hasLength(2));
  });

  test('Polygon hit test uses turf for inside, boundary, and outside points',
      () {
    final List<LatLng> points = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ];

    expect(containsLatLngInPolygon(points, const LatLng(5, 5)), isTrue);
    expect(containsLatLngInPolygon(points, const LatLng(0, 5)), isTrue);
    expect(containsLatLngInPolygon(points, const LatLng(11, 5)), isFalse);
  });

  test('Polygon hit test selects the last tappable matching polygon', () {
    final List<LatLng> points = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ];
    final List<String> tappedIds = <String>[];
    final Polygon first = Polygon(points: points, onTap: tappedIds.add);
    final Polygon second = Polygon(points: points, onTap: tappedIds.add);

    final Polygon? target = hitTestPolygonTapTarget(
      <Polygon>[first, second],
      const LatLng(5, 5),
    );
    target?.onTap?.call(target.id);

    expect(target, same(second));
    expect(tappedIds, <String>[second.id]);
  });

  test('Polygon hit test skips invisible polygons and polygons without onTap',
      () {
    final List<LatLng> points = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ];
    final List<String> tappedIds = <String>[];
    final Polygon active = Polygon(points: points, onTap: tappedIds.add);
    final Polygon hidden = Polygon(
      points: points,
      visible: false,
      onTap: tappedIds.add,
    );
    final Polygon noCallback = Polygon(points: points);

    expect(
      hitTestPolygonTapTarget(
        <Polygon>[active, hidden, noCallback],
        const LatLng(5, 5),
      ),
      same(active),
    );
    expect(
      hitTestPolygonTapTarget(
        <Polygon>[hidden, noCallback],
        const LatLng(5, 5),
      ),
      isNull,
    );
  });

  test('Polygon copyWith preserves onTap callback', () {
    final List<LatLng> points = <LatLng>[
      const LatLng(0, 0),
      const LatLng(0, 10),
      const LatLng(10, 10),
      const LatLng(10, 0),
    ];
    final List<String> tappedIds = <String>[];
    final Polygon polygon = Polygon(points: points, onTap: tappedIds.add);

    final Polygon copy = polygon.copyWith(fillColor: Colors.red);
    copy.onTap?.call(copy.id);

    expect(copy.onTap, same(polygon.onTap));
    expect(tappedIds, <String>[polygon.id]);
  });

  // setUp(() {
  //   channel.setMockMethodCallHandler((MethodCall methodCall) async {
  //     return '42';
  //   });
  // });

  // tearDown(() {
  //   channel.setMockMethodCallHandler(null);
  // });

  // // test('getPlatformVersion', () async {
  // //   expect(await AMapWiget.platformVersion, '42');
  // // });

  test('BitmapDescriptor wraps a JSON icon in the native descriptor protocol',
      () {
    final MarkerRenderIcon iconJson = MarkerRender.icon(
      view: MarkerRender.container(),
    );

    expect(BitmapDescriptor.fromJsonIcon(iconJson).toMap(), <dynamic>[
      'fromJsonIcon',
      <String, dynamic>{
        'view': <String, dynamic>{
          'type': 'container',
        },
      },
    ]);
  });

  test('MarkerRender stack serializes children without a child field', () {
    expect(
      MarkerRender.stack(
        style: const MarkerRenderStackStyle(
          width: 10,
          height: 12,
        ),
        children: <MarkerRenderNode>[
          MarkerRender.space(
            width: 1,
          ),
        ],
      ).toJson(),
      <String, dynamic>{
        'type': 'stack',
        'style': <String, dynamic>{
          'width': 10.0,
          'height': 12.0,
        },
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'space',
            'style': <String, dynamic>{
              'width': 1.0,
            },
          },
        ],
      },
    );
  });

  test('MarkerRenderAlignment exposes only canonical positions', () {
    expect(
      MarkerRenderAlignment.values
          .map((MarkerRenderAlignment value) => value.value),
      <String>[
        'center',
        'top|left',
        'top|right',
        'bottom|left',
        'bottom|right',
        'top|center',
        'bottom|center',
        'center|left',
        'center|right',
      ],
    );
  });

  test('MarkerRender serializes typed icon schema', () {
    final MarkerRenderIcon iconJson = MarkerRender.icon(
      view: MarkerRender.column(
        style: const MarkerRenderColumnStyle(
          alignment: MarkerRenderAlignment.center,
        ),
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
    );

    expect(iconJson.toJson(), <String, dynamic>{
      'view': <String, dynamic>{
        'type': 'column',
        'style': <String, dynamic>{
          'alignment': 'center',
        },
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'text': '18',
            'style': <String, dynamic>{
              'backgroundColor': '#FFE53935',
              'alignment': 'center',
              'includeFontPadding': false,
              'padding': <double>[8, 2, 8, 2],
              'radius': 10.0,
              'textColor': '#FFFFFFFF',
              'textSize': 12.0,
              'textStyle': 'bold',
            },
          },
          <String, dynamic>{
            'type': 'space',
            'style': <String, dynamic>{
              'height': 2.0,
            },
          },
          <String, dynamic>{
            'type': 'image',
            'src': <dynamic>['fromAsset', 'assets/marker_icon.png'],
            'style': <String, dynamic>{
              'width': 48.0,
              'height': 48.0,
            },
          },
        ],
      },
    });
  });

  test('MarkerRender serializes container schema', () {
    final MarkerRenderIcon iconJson = MarkerRender.icon(
      view: MarkerRender.container(
        style: const MarkerRenderContainerStyle(
          width: 64,
          alignment: MarkerRenderAlignment.center,
          backgroundColor: Color(0xFFFFFFFF),
          radius: 8,
        ),
        child: MarkerRender.image(
          const MarkerRenderAssetSource('assets/marker_icon.png'),
          style: const MarkerRenderImageStyle(
            width: 48,
            height: 48,
          ),
        ),
      ),
    );

    expect(iconJson.toJson(), <String, dynamic>{
      'view': <String, dynamic>{
        'type': 'container',
        'style': <String, dynamic>{
          'width': 64.0,
          'alignment': 'center',
          'backgroundColor': '#FFFFFFFF',
          'radius': 8.0,
        },
        'child': <String, dynamic>{
          'type': 'image',
          'src': <dynamic>['fromAsset', 'assets/marker_icon.png'],
          'style': <String, dynamic>{
            'width': 48.0,
            'height': 48.0,
          },
        },
      },
    });
  });

  test('MarkerRender container omits children', () {
    expect(
      MarkerRenderGroupNode(
        type: MarkerRenderNodeType.container,
        children: <MarkerRenderNode>[
          MarkerRender.space(width: 1, height: 1),
        ],
      ).toJson(),
      <String, dynamic>{
        'type': 'container',
      },
    );
  });

  test('MarkerRender serializes nested layout schema', () {
    final MarkerRenderIcon iconJson = MarkerRender.icon(
      view: MarkerRender.container(
        style: const MarkerRenderContainerStyle(
          width: 96,
          height: 72,
          padding: MarkerRenderInsets.all(4),
          alignment: MarkerRenderAlignment.center,
          backgroundColor: Color(0x66000000),
          radius: 12,
        ),
        child: MarkerRender.stack(
          style: const MarkerRenderStackStyle(
            width: 88,
            height: 64,
            alignment: MarkerRenderAlignment.bottomCenter,
          ),
          children: <MarkerRenderNode>[
            MarkerRender.image(
              const MarkerRenderAssetSource(
                'assets/marker_bg.png',
                package: 'amap_map2',
              ),
              style: const MarkerRenderImageStyle(
                width: 88,
                height: 64,
              ),
            ),
            MarkerRender.column(
              style: const MarkerRenderColumnStyle(
                alignment: MarkerRenderAlignment.center,
              ),
              children: <MarkerRenderNode>[
                MarkerRender.row(
                  style: const MarkerRenderRowStyle(
                    alignment: MarkerRenderAlignment.center,
                  ),
                  children: <MarkerRenderNode>[
                    MarkerRender.image(
                      const MarkerRenderAssetSource(
                        'assets/uav.png',
                      ),
                      style: const MarkerRenderImageStyle(
                        width: 16,
                        height: 16,
                        margin: MarkerRenderInsets.fromLTRB(0, 0, 4, 0),
                      ),
                    ),
                    MarkerRender.text(
                      'A01',
                      style: const MarkerRenderTextStyle(
                        textColor: Color(0xFFFFFFFF),
                        textSize: 11,
                        singleLine: true,
                        includeFontPadding: false,
                      ),
                    ),
                  ],
                ),
                MarkerRender.space(
                  height: 4,
                ),
                MarkerRender.text(
                  '在线',
                  style: const MarkerRenderTextStyle(
                    textColor: Color(0xFF00E676),
                    textSize: 10,
                    fontWeight: MarkerRenderFontWeight.w700,
                    includeFontPadding: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(iconJson.toJson(), <String, dynamic>{
      'view': <String, dynamic>{
        'type': 'container',
        'style': <String, dynamic>{
          'width': 96.0,
          'height': 72.0,
          'padding': <double>[4, 4, 4, 4],
          'alignment': 'center',
          'backgroundColor': '#66000000',
          'radius': 12.0,
        },
        'child': <String, dynamic>{
          'type': 'stack',
          'style': <String, dynamic>{
            'width': 88.0,
            'height': 64.0,
            'alignment': 'bottom|center',
          },
          'children': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'image',
              'src': <dynamic>[
                'fromAsset',
                'assets/marker_bg.png',
                'amap_map2',
              ],
              'style': <String, dynamic>{
                'width': 88.0,
                'height': 64.0,
              },
            },
            <String, dynamic>{
              'type': 'column',
              'style': <String, dynamic>{
                'alignment': 'center',
              },
              'children': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'row',
                  'style': <String, dynamic>{
                    'alignment': 'center',
                  },
                  'children': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'type': 'image',
                      'src': <dynamic>['fromAsset', 'assets/uav.png'],
                      'style': <String, dynamic>{
                        'width': 16.0,
                        'height': 16.0,
                        'margin': <double>[0, 0, 4, 0],
                      },
                    },
                    <String, dynamic>{
                      'type': 'text',
                      'text': 'A01',
                      'style': <String, dynamic>{
                        'textColor': '#FFFFFFFF',
                        'textSize': 11.0,
                        'singleLine': true,
                        'includeFontPadding': false,
                      },
                    },
                  ],
                },
                <String, dynamic>{
                  'type': 'space',
                  'style': <String, dynamic>{
                    'height': 4.0,
                  },
                },
                <String, dynamic>{
                  'type': 'text',
                  'text': '在线',
                  'style': <String, dynamic>{
                    'textColor': '#FF00E676',
                    'textSize': 10.0,
                    'fontWeight': '700',
                    'includeFontPadding': false,
                  },
                },
              ],
            },
          ],
        },
      },
    });
  });

  test('MarkerRender serializes image text row composition', () {
    final MarkerRenderIcon iconJson = MarkerRender.icon(
      view: MarkerRender.row(
        style: const MarkerRenderRowStyle(
          margin: MarkerRenderInsets.symmetric(horizontal: 2, vertical: 3),
          alignment: MarkerRenderAlignment.center,
        ),
        children: <MarkerRenderNode>[
          MarkerRender.image(
            const MarkerRenderAssetSource('assets/avatar.png'),
            style: const MarkerRenderImageStyle(
              width: 24,
              height: 24,
              margin: MarkerRenderInsets.fromLTRB(0, 0, 6, 0),
            ),
          ),
          MarkerRender.text(
            'Dispatcher',
            style: const MarkerRenderTextStyle(
              width: 80,
              height: 22,
              alignment: MarkerRenderAlignment.centerLeft,
              textColor: Color(0xFF263238),
              textSize: 13,
              ellipsize: MarkerRenderEllipsize.middle,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );

    expect(iconJson.toJson(), <String, dynamic>{
      'view': <String, dynamic>{
        'type': 'row',
        'style': <String, dynamic>{
          'margin': <double>[2, 3, 2, 3],
          'alignment': 'center',
        },
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'image',
            'src': <dynamic>['fromAsset', 'assets/avatar.png'],
            'style': <String, dynamic>{
              'width': 24.0,
              'height': 24.0,
              'margin': <double>[0, 0, 6, 0],
            },
          },
          <String, dynamic>{
            'type': 'text',
            'text': 'Dispatcher',
            'style': <String, dynamic>{
              'width': 80.0,
              'height': 22.0,
              'alignment': 'center|left',
              'textColor': '#FF263238',
              'textSize': 13.0,
              'maxLines': 1,
              'ellipsize': 'middle',
            },
          },
        ],
      },
    });
  });

  test('MarkerRender serializes direct node constructors', () {
    const MarkerRenderIcon iconJson = MarkerRenderIcon(
      view: MarkerRenderGroupNode(
        type: MarkerRenderNodeType.stack,
        style: MarkerRenderStackStyle(
          width: 40,
          height: 40,
          margin: MarkerRenderInsets.all(1),
          alignment: MarkerRenderAlignment.topRight,
        ),
        children: <MarkerRenderNode>[
          MarkerRenderSpaceNode(
            width: 4,
            height: 4,
          ),
          MarkerRenderTextNode(
            text: '!',
            style: MarkerRenderTextStyle(
              backgroundColor: Color(0xFFFFEB3B),
              radius: 6,
              padding: MarkerRenderInsets.symmetric(
                horizontal: 3,
                vertical: 1,
              ),
              textColor: Color(0xFF000000),
              textStyle: MarkerRenderTextStyleValue.boldItalic,
            ),
          ),
        ],
      ),
    );

    expect(iconJson.toJson(), <String, dynamic>{
      'view': <String, dynamic>{
        'type': 'stack',
        'style': <String, dynamic>{
          'width': 40.0,
          'height': 40.0,
          'margin': <double>[1, 1, 1, 1],
          'alignment': 'top|right',
        },
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'space',
            'style': <String, dynamic>{
              'width': 4.0,
              'height': 4.0,
            },
          },
          <String, dynamic>{
            'type': 'text',
            'text': '!',
            'style': <String, dynamic>{
              'padding': <double>[3, 1, 3, 1],
              'backgroundColor': '#FFFFEB3B',
              'radius': 6.0,
              'textColor': '#FF000000',
              'textStyle': 'boldItalic',
            },
          },
        ],
      },
    });
  });
}
