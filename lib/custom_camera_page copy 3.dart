// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';
// import 'dart:async';

// import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
// import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
// import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
// import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
// import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
// import 'package:ar_flutter_plugin_2/models/ar_node.dart';
// import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';

// import 'package:flutter/material.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:vector_math/vector_math_64.dart' as vm;
// import 'package:webview_flutter/webview_flutter.dart';

// void main() => runApp(const MaterialApp(home: SphereScanPage()));

// class SphereScanPage extends StatefulWidget {
//   const SphereScanPage({Key? key}) : super(key: key);

//   @override
//   State<SphereScanPage> createState() => _SphereScanPageState();
// }

// class _SphereScanPageState extends State<SphereScanPage> {
//   /* AR 核心管理器 */
//   late ARSessionManager arSessionManager;
//   late ARObjectManager arObjectManager;
//   late ARAnchorManager arAnchorManager;
//   late ARLocationManager arLocationManager;
//   Timer? _frameTimer;

//   /* WebView 核心 */
//   late WebViewController _webViewController;
//   bool _isWebViewLoaded = false;

//   /* 校准与固定中心点（关键修改：关联物体平面） */
//   bool isCalibrated = false; 
//   Matrix4? initialCalibrationPose; 
//   vm.Vector3? fixedCenter3D; // 与物体重合的固定3D中心点
//   ARPlaneAnchor? objectPlaneAnchor; // 物体所在平面的锚点（用于稳定中心点）
//   double _centerToCameraDistance = 0.0; // 中心点到相机的实时距离（米）

//   /* 采样参数 */
//   final int thetaSteps = 18;
//   final int phiSteps = 9;
//   final double radius = 0.5;
  
//   List<List<int>> sampledIndices = [];
//   Set<String> sampledKeys = {};
//   bool scanning = false;
//   int totalCells = 0;
//   late Directory saveDir;

//   @override
//   void initState() {
//     super.initState();
//     _initARData();
//     _initWebView();
//   }

//   Future<void> _initARData() async {
//     final temp = await getTemporaryDirectory();
//     saveDir = Directory('${temp.path}/sphere_scan')..createSync(recursive: true);
//     totalCells = thetaSteps * phiSteps;
//     if (mounted) setState(() {});
//   }

//   void _initWebView() {
//     _webViewController = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..setBackgroundColor(const Color(0x00000000))
//       ..setNavigationDelegate(NavigationDelegate(
//         onPageFinished: (String url) {
//           setState(() => _isWebViewLoaded = true);
//           _syncSampledDots();
//         },
//         onWebResourceError: (error) => print('WebView加载错误: ${error.description}'),
//       ))
//       ..loadFlutterAsset('dist/ball.html');
//   }

//   void _syncSampledDots() {
//     if (!_isWebViewLoaded || sampledIndices.isEmpty) return;
//     _webViewController.runJavaScript(
//       'markSampledAreas(${jsonEncode(sampledIndices)})'
//     );
//   }

//   void onARViewCreated(
//     ARSessionManager sm,
//     ARObjectManager om,
//     ARAnchorManager am,
//     ARLocationManager lm,
//   ) async {
//     arSessionManager = sm;
//     arObjectManager = om;
//     arAnchorManager = am;
//     arLocationManager = lm;

//     // 关键：启用平面检测（识别物体所在平面）
//     arSessionManager.onInitialize(
//       showAnimatedGuide: true, // 显示平面检测引导
//       showFeaturePoints: false, // 显示特征点（辅助判断物体位置）
//       showPlanes: true, // 显示检测到的平面（蓝色网格）
//       showWorldOrigin: true,
//     );

//     // 关键：添加AR视图点击监听（选择物体位置）
//     arSessionManager.onPlaneOrPointTap = _onPlaneTap;

//     // 帧循环：仅在校准后执行采样、姿态传递、距离计算
//     _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
//       // 1. 实时计算中心点到相机的距离（基于物体平面锚点更新）
//       // if (isCalibrated && fixedCenter3D != null && objectPlaneAnchor != null) {
//       //   // 刷新平面锚点的最新姿态（防止物体轻微位移导致偏差）
//       //   // await arAnchorManager.getAnchorPose(objectPlaneAnchor!.identifier);
//       //   final camPose = await arSessionManager.getCameraPose();
//       //   if (camPose != null) {
//       //     _calculateCenterToCameraDistance(camPose);
//       //   }
//       // }
//       final camPose = await arSessionManager.getCameraPose();
//       if(camPose == null) return;

//       // 2. 采样逻辑
//       if (scanning && isCalibrated && fixedCenter3D != null) {
//         await _onFrameSample(camPose);
//       }
      
//       // 3. 姿态传递逻辑
//       if (isCalibrated && initialCalibrationPose != null) {
//         if (_isWebViewLoaded) {
//           _sendPoseToWebView(camPose);
//         }
//       }
//     });
//   }

//   /* 关键修改：AR平面点击事件（选择物体位置作为中心点） */
//   Future<void> _onPlaneTap(List<ARHitTestResult> hitTestResults) async {
//     // 过滤：只保留平面点击结果（确保点击到物体所在平面）
//     final planeHit = hitTestResults.firstWhere(
//       (result) => result.type == ARHitTestResultType.plane,
//       orElse: () => throw StateError("未点击到平面"),
//     );

//     try {
//       // 1. 在点击位置创建平面锚点（绑定物体所在平面，确保位置稳定）
//       objectPlaneAnchor = ARPlaneAnchor(
//           transformation:planeHit.worldTransform
//       );
//       await arAnchorManager.addAnchor(
//         objectPlaneAnchor!
//       );

//       final indicatorNode = ARNode(
//         type: NodeType.localGLTF2,
//         uri:
//           "dist/scene.gltf",
        
//         scale: vm.Vector3.all(0.05),
//         position: vm.Vector3.all(0),
//       );

//       await arObjectManager.addNode(indicatorNode, planeAnchor: objectPlaneAnchor);

//       fixedCenter3D = planeHit.worldTransform.getColumn(3).xyz; // 提取点击位置的3D坐标

//       // 3. 初始化校准状态和距离
//       final currentCamPose = await arSessionManager.getCameraPose();
//       if (currentCamPose != null) {
//         initialCalibrationPose = currentCamPose;
//         // _calculateCenterToCameraDistance(currentCamPose); // 初始距离计算
//       }

//       // 4. 更新UI状态
//       setState(() => isCalibrated = true);
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('中心点已与物体重合！'),
//           backgroundColor: Colors.green,
//           duration: Duration(seconds: 1),
//         ),
//       );
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('选择物体失败：${e.toString()}'),
//           backgroundColor: Colors.red,
//           duration: Duration(seconds: 1),
//         ),
//       );
//     }
//   }

//   /* 计算中心点到相机的实时距离 */
//   void _calculateCenterToCameraDistance(Matrix4 camPose) {
//     if (fixedCenter3D == null) return;
    
//     // 1. 获取当前相机的3D位置（世界坐标系）
//     final camPos = camPose.getColumn(3).xyz;
//     camPos.z = -camPos.z; // 坐标系方向修正（AR与Three.js适配）

//     // 2. 计算相机到物体中心点的欧几里得距离
//     final distance = (fixedCenter3D! - camPos).length;

//     // 3. 更新状态（保留2位小数，避免UI频繁刷新）
//     if (mounted && (distance - _centerToCameraDistance).abs() > 0.01) {
//       setState(() {
//         _centerToCameraDistance = double.parse(distance.toStringAsFixed(2));
//       });
//     }
//   }

//   /* 计算相对姿态 */
//   Matrix4 _calculateRelativePose(Matrix4 initialPose, Matrix4 currentPose) {
//     return Matrix4.tryInvert(initialPose)! * currentPose;
//   }

//   // 控制相机视角（传递物体中心点相对姿态）
//   void _sendPoseToWebView(Matrix4 camPose) {
//     if (fixedCenter3D == null) return;

//     // 1. 计算相机相对于物体中心点的位置向量
//     final camPos = camPose.getColumn(3).xyz;
//     final relativePos = (camPos - fixedCenter3D!).normalized();

//     // 2. 转换为球面坐标（用于WebView视角同步）
//     final theta = atan2(relativePos.z, relativePos.x); // 方位角（-π~π）
//     final phi = atan2(relativePos.y, sqrt(relativePos.x*relativePos.x + relativePos.z*relativePos.z)); // 俯仰角（-π/2~π/2）

//     // 3. 角度转换（弧度→角度）并传递给WebView
//     final thetaDeg = theta * 180 / pi;
//     final phiDeg = phi * 180 / pi;
//     _webViewController.runJavaScript(
//       'updateSphereView($thetaDeg, $phiDeg)'
//     );
//   }

//   /* 核心：计算当前视场内的圆点索引（基于物体中心点） */
//   (List<int>, List<int>) _currentCells(Matrix4 camPose) {
//     if (fixedCenter3D == null) return ([], []);

//     // 1. 计算相机指向物体中心点的方向向量
//     final camPos = camPose.getColumn(3).xyz;
//     final dir = (fixedCenter3D! - camPos).normalized();

//     // 2. 转换为球面坐标并映射到索引
//     final phi = atan2(dir.y, sqrt(dir.x* dir.x + dir.z * dir.z)); 
//     final theta = atan2(dir.z, dir.x); 

//     // 3. 索引范围计算（避免越界）
//     final centerPhiIdx = (( (phi + pi/2) / pi ) * phiSteps).round().clamp(0, phiSteps - 1);
//     final centerThetaIdx = (((theta + pi) / (2 * pi)) * thetaSteps).round().clamp(0, thetaSteps - 1);

//     // 4. 检测范围（可根据需求调整）
//     const phiRange = 1; // 纵向检测范围：±1行
//     const thetaRange = 2; // 横向检测范围：±2列
//     final minPhiIdx = (centerPhiIdx - phiRange).clamp(0, phiSteps - 1);
//     final maxPhiIdx = (centerPhiIdx + phiRange).clamp(0, phiSteps - 1);
//     final minThetaIdx = (centerThetaIdx - thetaRange).clamp(0, thetaSteps - 1);
//     final maxThetaIdx = (centerThetaIdx + thetaRange).clamp(0, thetaSteps - 1);

//     // 5. 收集有效索引
//     final List<int> phiIndices = [];
//     final List<int> thetaIndices = [];
//     for (int p = minPhiIdx; p <= maxPhiIdx; p++) phiIndices.add(p);
//     for (int t = minThetaIdx; t <= maxThetaIdx; t++) thetaIndices.add(t);

//     return (phiIndices, thetaIndices);
//   }

//   /* 帧采样逻辑（仅在校准后执行） */
//   Future<void> _onFrameSample(pose) async {
//     if (!isCalibrated || fixedCenter3D == null) return;
    
//     final (phiIndices, thetaIndices) = _currentCells(pose);
    
//     for (final phiIdx in phiIndices) {
//       for (final thetaIdx in thetaIndices) {
//         final sampleKey = '$phiIdx\_$thetaIdx';
//         if (!sampledKeys.contains(sampleKey)) {
//           sampledIndices.add([phiIdx, thetaIdx]);
//           sampledKeys.add(sampleKey);

//           // 保存采样数据（关联物体中心点的姿态）
//           final poseFile = File('${saveDir.path}/$sampleKey.json');
//           await poseFile.writeAsString(jsonEncode(pose.storage.toList()));

//           // 刷新UI和WebView
//           setState(() {});
//           if (_isWebViewLoaded) {
//             _webViewController.runJavaScript(
//               'markSampledArea($phiIdx, $thetaIdx)'
//             );
//           }
//         }
//       }
//     }
//   }

//   /* 采样开关（仅在校准后可点击） */
//   void _toggleScan() {
//     if (!isCalibrated) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('请先点击画面中的物体，设置重合中心点'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//       return;
//     }
//     setState(() => scanning = !scanning);
//   }

//   /* 清除逻辑（重置物体中心点和平面锚点） */
//   Future<void> _clear() async {
//     // 1. 删除物体平面锚点（释放AR资源）
//     // if (objectPlaneAnchor != null) {
//     //   await arAnchorManager.removeAnchor(objectPlaneAnchor!.identifier);
//     //   objectPlaneAnchor = null;
//     // }

//     // 2. 重置所有状态
//     setState(() {
//       scanning = false;
//       sampledIndices.clear();
//       sampledKeys.clear();
//       isCalibrated = false;
//       initialCalibrationPose = null;
//       fixedCenter3D = null;
//       _centerToCameraDistance = 0.0;
//     });

//     // 3. 清除本地数据和WebView状态
//     await saveDir.delete(recursive: true);
//     saveDir.createSync(recursive: true);
//     if (_isWebViewLoaded) {
//       _webViewController.runJavaScript('clearAllSamples()');
//     }
    
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('已重置，可重新点击物体设置中心点')),
//     );
//   }

//   @override
//   void dispose() {
//     _frameTimer?.cancel();
//     // 释放AR资源（避免内存泄漏）
//     // if (objectPlaneAnchor != null) {
//     //   arAnchorManager.removeAnchor(objectPlaneAnchor!.identifier);
//     // }
//     super.dispose();
//   }

//   /* 完整UI布局：AR预览+点击引导+中心点标记+距离显示+采样控制 */
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       // 顶部导航栏：标题+重置按钮
//       appBar: AppBar(
//         title: const Text('物体中心点采样'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh, color: Colors.white),
//             onPressed: _clear, // 点击重置所有状态
//             tooltip: "重置采样",
//           )
//         ],
//         backgroundColor: Colors.red,
//         elevation: 4,
//       ),
//       // 主内容区：Stack层叠布局（AR视图在最下层，其他UI在上方）
//       body: Stack(
//         children: [
//           // 1. 底层：AR相机预览（核心，显示实时画面并支持点击选择物体）
//           ARView(
//             onARViewCreated: onARViewCreated,
//             planeDetectionConfig: PlaneDetectionConfig.horizontal, 
//             // 若物体是垂直的（如墙面海报），替换为：PlaneDetectionConfig.vertical
//           ),

//           // 2. 未校准时：显示“点击物体”引导提示（居中）
//           if (!isCalibrated)
//             const Align(
//               alignment: Alignment.center,
//               child: DecoratedBox(
//                 decoration: BoxDecoration(
//                   color: Colors.black54,
//                   borderRadius: BorderRadius.all(Radius.circular(8)),
//                   boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
//                 ),
//                 child: Padding(
//                   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                   child: Text(
//                     '请点击画面中的物体对应的底面',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       height: 1.2,
//                     ),
//                     textAlign: TextAlign.center,
//                   ),
//                 ),
//               ),
//             ),

//           // 3. 已校准时：显示中心点标记（屏幕中心红色圆点，对应物体位置）
//           if (isCalibrated)
//             const Align(
//               alignment: Alignment.center,
//               child: Icon(
//                 Icons.circle,
//                 color: Colors.red,
//                 size: 20,
//                 shadows: [Shadow(color: Colors.red, blurRadius: 5)],
//               ),
//             ),

//           // 4. 右上角：WebView小球+校准状态+距离显示+采样进度
//           Align(
//             alignment: Alignment.topRight,
//             child: Padding(
//               padding: const EdgeInsets.all(20),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min, // 仅占用子元素所需高度
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   // 4.1 WebView小球（显示3D采样可视化）
//                   SizedBox(
//                     width: 180,
//                     height: 180,
//                     child: WebViewWidget(
//                       controller: _webViewController,
//                       layoutDirection: TextDirection.ltr,
//                     ),
//                   ),
//                   const SizedBox(height: 8),

//                   // 4.2 校准状态提示（已校准/未校准）
//                   DecoratedBox(
//                     decoration: BoxDecoration(
//                       color: isCalibrated ? Colors.green.withOpacity(0.8) : Colors.grey.withOpacity(0.8),
//                       borderRadius: BorderRadius.all(Radius.circular(4)),
//                     ),
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       child: Text(
//                         isCalibrated ? '已校准' : '未校准',
//                         style: const TextStyle(color: Colors.white, fontSize: 12),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 4),

//                   // 4.3 实时距离显示（仅已校准时显示）
//                   const SizedBox(height: 4),

//                   // 4.4 采样进度（已采样数/总采样数）
//                   DecoratedBox(
//                     decoration: BoxDecoration(
//                       color: Colors.black54,
//                       borderRadius: BorderRadius.all(Radius.circular(4)),
//                     ),
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       child: Text(
//                         '采样进度：${sampledIndices.length} / $totalCells',
//                         style: const TextStyle(color: Colors.white, fontSize: 12),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),

//           // 5. 底部：采样开关按钮（未校准则置灰）
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: Padding(
//               padding: const EdgeInsets.only(bottom: 40),
//               child: ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: isCalibrated ? Colors.red : Colors.grey[500],
//                   padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.all(Radius.circular(8)),
//                   ),
//                   elevation: 6,
//                 ),
//                 onPressed: _toggleScan, // 切换开始/停止采样
//                 child: Text(
//                   scanning ? '停止采样' : '开始采样',
//                   style: const TextStyle(
//                     fontSize: 16,
//                     color: Colors.white,
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }