import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

class LightWeightRecorder {
  static const MethodChannel _channel =
      MethodChannel('lightweight_recorder');

  /// 开始录视频
  Future<void> startVideoRecording({String? fileName}) async {
    await _channel.invokeMethod('start', {'name': fileName});
  }

  /// 停止录视频，返回 XFile
  Future<XFile> stopVideoRecording() async {
    final String path = await _channel.invokeMethod('stop');
    return XFile(path);
  }
}