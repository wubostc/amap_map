import 'dart:typed_data';

import 'package:amap_map2/amap_map2.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

class SnapshotPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SnapShotState();
}

class _SnapShotState extends State<SnapshotPage> {
  AMapController? _mapController;
  Uint8List? _imageBytes;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: AMapWidget(
              onMapCreated: _onMapCreated,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: Row(
              children: <Widget>[
                Expanded(child: _snapshotButton()),
                const SizedBox(width: 12),
                Expanded(child: _regionSnapshotButton()),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Colors.blueGrey[50]),
              child: _imageBytes != null ? Image.memory(_imageBytes!) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotButton() {
    return SizedBox(
      height: 40,
      child: TextButton(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          //文字颜色
          foregroundColor: WidgetStateProperty.all(Colors.white),
          //水波纹颜色
          overlayColor: WidgetStateProperty.all(Colors.blueAccent),
          //背景颜色
          backgroundColor:
              WidgetStateProperty.resolveWith((Set<WidgetState> states) {
            //设置按下时的背景颜色
            if (states.contains(WidgetState.pressed)) {
              return Colors.blueAccent;
            }
            //默认背景颜色
            return Colors.blue;
          }),
        ),
        onPressed: () async {
          final Uint8List? imageBytes = await _mapController?.takeSnapshot();
          if (mounted) {
            setState(() => _imageBytes = imageBytes);
          }
        },
        child: const Text('截屏'),
      ),
    );
  }

  Widget _regionSnapshotButton() {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: () async {
          final Uint8List? imageBytes =
              await _mapController?.takeRegionSnapshot(
            topLeft: const LatLng(39.95, 116.30),
            topRight: const LatLng(39.95, 116.50),
            width: 800,
            height: 600,
          );
          if (mounted && imageBytes != null) {
            setState(() => _imageBytes = imageBytes);
          }
        },
        child: const Text('区域截图'),
      ),
    );
  }

  void _onMapCreated(AMapController controller) {
    _mapController = controller;
  }
}
