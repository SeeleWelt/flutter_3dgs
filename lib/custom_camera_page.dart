import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:webview_flutter/webview_flutter.dart';

class SphereScanPage extends StatefulWidget {
  final Function(File) onRecordComplete;

  const SphereScanPage({
    super.key,
    required this.onRecordComplete,
  });

  @override
  State<SphereScanPage> createState() => _SphereScanPageState();
}

class _SphereScanPageState extends State<SphereScanPage> {
  // 原逻辑变量保留
  late ARSessionManager arSessionManager;
  late ARObjectManager arObjectManager;
  late ARAnchorManager arAnchorManager;
  late ARLocationManager arLocationManager;
  Timer? _frameTimer;

  late WebViewController _webViewController;
  bool _isWebViewLoaded = false;

  bool isCalibrated = false;
  Matrix4? initialCalibrationPose;
  vm.Vector3? fixedCenter3D;
  ARPlaneAnchor? objectPlaneAnchor;
  ARNode? indicatorNode;
  String nodeName = "center";

  final int thetaSteps = 18;
  final int phiSteps = 9;
  final double radius = 0.5;
  List<List<int>> sampledIndices = [];
  Set<String> sampledKeys = {};
  bool scanning = false;

  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  bool _arCoreReady = false;


  // 新增：文件名输入控制器
  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initARData();
    _initWebView();
    // 初始化默认文件名
    _fileNameController.text = DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> _initARData() async {
    setState(() {});
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _isWebViewLoaded = true),
        onWebResourceError: (e) => debugPrint('WebView 错误: $e'),
      ))
      ..loadFlutterAsset('assets/ball.html'); // 修复资源路径拼写错误
  }

  void onARViewCreated(
    ARSessionManager sm,
    ARObjectManager om,
    ARAnchorManager am,
    ARLocationManager lm,
  ) {
    arSessionManager = sm;
    arObjectManager = om;
    arAnchorManager = am;
    arLocationManager = lm;

    arSessionManager.onInitialize(
      showAnimatedGuide: true,
      showFeaturePoints: false,
      showPlanes: false,
      showWorldOrigin: false,
    );
    arSessionManager.onPlaneOrPointTap = _onPlaneTap;

    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!_arCoreReady) {
        final testPose = await arSessionManager.getCameraPose();
        if (testPose != null) setState(() => _arCoreReady = true);
        return;
      }

      final camPose = await arSessionManager.getCameraPose();
      if (camPose == null) return;

      if (scanning && isCalibrated && fixedCenter3D != null) {
        await _onFrameSample(camPose);
      }
      if (isCalibrated && initialCalibrationPose != null && _isWebViewLoaded) {
        _sendPoseToWebView(camPose);
      }
    });
  }

  Future<void> _onPlaneTap(List<ARHitTestResult> hits) async {
    if(isCalibrated) return;
    final hit = hits.where((h) => h.type == ARHitTestResultType.plane).firstOrNull;
    if (hit == null) return;

    objectPlaneAnchor = ARPlaneAnchor(transformation: hit.worldTransform);
    await arAnchorManager.addAnchor(objectPlaneAnchor!);

    indicatorNode = ARNode(
      name: nodeName,
      type: NodeType.localGLTF2,
      uri: "assets/scene.gltf", // 修复资源路径拼写错误
      scale: vm.Vector3.all(0.05),
      position: vm.Vector3.zero(),
    );
    await arObjectManager.addNode(indicatorNode!, planeAnchor: objectPlaneAnchor);

    fixedCenter3D = hit.worldTransform.getColumn(3).xyz;
    initialCalibrationPose = await arSessionManager.getCameraPose();
    setState(() => isCalibrated = true);
  }

  void _sendPoseToWebView(Matrix4 camPose) {
    if (fixedCenter3D == null) return;
    final dir = (camPose.getColumn(3).xyz - fixedCenter3D!).normalized();
    final theta = atan2(dir.z, dir.x);
    final phi = atan2(dir.y, sqrt(dir.x * dir.x + dir.z * dir.z));
    _webViewController.runJavaScript(
        'updateSphereView(${theta * 180 / pi}, ${phi * 180 / pi})');
  }

  (List<int>, List<int>) _currentCells(Matrix4 camPose) {
    if (fixedCenter3D == null) return ([], []);
    final dir = (fixedCenter3D! - camPose.getColumn(3).xyz).normalized();
    final phi = atan2(dir.y, sqrt(dir.x * dir.x + dir.z * dir.z));
    final theta = atan2(dir.z, dir.x);
    final pIdx = (((phi + pi / 2) / pi) * phiSteps).round().clamp(0, phiSteps - 1);
    final tIdx = (((theta + pi) / (2 * pi)) * thetaSteps).round().clamp(0, thetaSteps - 1);
    const pR = 1, tR = 2;
    return (
      List.generate(2 * pR + 1, (i) => (pIdx - pR + i).clamp(0, phiSteps - 1)),
      List.generate(2 * tR + 1, (i) => (tIdx - tR + i).clamp(0, thetaSteps - 1))
    );
  }

  Future<void> _onFrameSample(Matrix4 pose) async {
    final (phiIdxs, thetaIdxs) = _currentCells(pose);
    for (final p in phiIdxs) {
      for (final t in thetaIdxs) {
        final key = '${p}_$t';
        if (sampledKeys.add(key)) {
          sampledIndices.add([p, t]);
          if (_isWebViewLoaded) {
            _webViewController.runJavaScript('markSampledArea($p, $t)');
          }
        }
      }
    }
  }

  /* ----------------- 录屏相关（修改部分） ----------------- */
  Future<void> _startRecording() async {
    if (_isRecording) return;
    // 使用当前输入的文件名开始录制
    await arSessionManager.startRecording(fileName: "temp");
    _isRecording = true;
    _recordDuration = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _recordDuration++);
      if (_recordDuration >= 300) _stopRecording();
    });
    setState(() {});
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    final path = await arSessionManager.stopRecording();
    if (path == null) return;

    // 显示文件名输入弹窗
    bool _isCancel = await _showFileNameDialog();

    // 处理用户输入的文件名
    if (mounted && _fileNameController.text.isNotEmpty) {
      final originalFile = File(path);
      final Directory? appExternalDir = await getExternalStorageDirectory();
      final Directory publicRootDir = appExternalDir!.parent.parent.parent.parent;
      final String dir = "${publicRootDir.path}/Movies";
      final String targetFileName = "${_fileNameController.text}.mp4";
      final String savePath = "$dir/$targetFileName";
      final String originalPath = "$dir/${originalFile.name}";
      print("mylog: $path, $savePath, $originalPath");
      // 执行文件复制+删除原文件
      try {
        if(!_isCancel)
        {
          final File curFile = await originalFile.copy(savePath);
          widget.onRecordComplete(curFile);

        }
        await originalFile.delete(); // 复制成功后再删原文件，避免丢失
        if(File(originalPath).existsSync())
        {
          await File(originalPath).delete();
        }
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        // 捕获文件操作异常（如权限不足），给用户提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("文件保存失败：${e.toString().substring(0, 50)}")),
          );
        }
      }
    }
  }

  // 新增：文件名输入弹窗
  Future<bool> _showFileNameDialog() async {
    bool _isCancel = false;
    await showDialog(
      context: context,
      barrierDismissible: false, // 点击外部不关闭
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.blueAccent, width: 0.5),
          ),
          title: const Text(
            "保存采样文件",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 带渐变边框的输入框
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
                  ),
                ),
                child: TextField(
                  controller: _fileNameController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black54,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                    hintText: "请输入文件名",
                    hintStyle: const TextStyle(color: Colors.white54),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () => _fileNameController.clear(),
                    ),
                  ),
                  // 过滤特殊字符
                  onChanged: (value) {
                    final filtered = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
                    if (filtered != value) {
                      _fileNameController.text = filtered;
                      _fileNameController.selection = TextSelection.fromPosition(
                        TextPosition(offset: filtered.length),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "无需输入文件后缀",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () { _isCancel = true; Navigator.pop(context);},
              child: const Text(
                "取消",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4facfe),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                if (_fileNameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("请输入文件名"),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
              },
              child: const Text("确认保存"),
            ),
          ],
        );
      },
    );
    return _isCancel;
  }

  String _formatDuration() =>
      '${(_recordDuration ~/ 60).toString().padLeft(2, '0')}'
      ':${(_recordDuration % 60).toString().padLeft(2, '0')}';

  void _toggleScan() {
    if (!isCalibrated) {
      ScaffoldMessenger.of(Navigator.of(context).overlay!.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('请先点击物体底面设置中心点'),
          backgroundColor: Colors.orange,
        ));
      return;
    }
    scanning ? _stopRecording() : _startRecording();
    setState(() => scanning = !scanning);
  }

  Future<void> _reset() async {
    if (_isRecording) await _stopRecording();
    if (objectPlaneAnchor != null) {
      await arAnchorManager.removeAnchor(objectPlaneAnchor!);
      objectPlaneAnchor = null;
    }
    if (indicatorNode != null) {
      await arObjectManager.removeNode(indicatorNode!);
      indicatorNode = null;
    }
    // 重置文件名
    _fileNameController.text = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      scanning = false;
      sampledIndices.clear();
      sampledKeys.clear();
      isCalibrated = false;
      initialCalibrationPose = null;
      fixedCenter3D = null;
    });
    if (_isWebViewLoaded) {
      _webViewController.runJavaScript('clearAllSamples()');
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _recordTimer?.cancel();
    _fileNameController.dispose(); // 释放控制器
    if (objectPlaneAnchor != null) {
      arAnchorManager.removeAnchor(objectPlaneAnchor!);
    }
    super.dispose();
  }

  /* ----------------- UI 部分 ----------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // AR 视图
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),

          // 中心提示
          if (!isCalibrated)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '请点击物体底面设置中心点',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),

          // 右上角球 + 状态
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 球
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white10,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: WebViewWidget(controller: _webViewController),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 录制时长
                    if (_isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatDuration(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 底部主按钮
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isCalibrated ? (scanning ? Colors.green : Colors.red) : Colors.grey,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _toggleScan,
                  child: Text(
                    scanning ? '停止采样' : '开始采样',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),

          // 浮动重置按钮
          Positioned(
            top: 40,
            left: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white24,
              onPressed: _reset,
              tooltip: '重置',
              child: const Icon(Icons.refresh, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// 扩展方法：获取文件名
extension FileName on File {
  String get name => path.split('/').last;
}