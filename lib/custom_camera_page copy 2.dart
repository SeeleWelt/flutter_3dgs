// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';
// import 'dart:async';

// import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
// import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
// import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
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

//   /* 校准与固定中心点 */
//   bool isCalibrated = false; 
//   Matrix4? initialCalibrationPose; 
//   vm.Vector3? fixedCenter3D; // 校准后固定的3D中心点（核心新增）
//   double _centerToCameraDistance = 0.0; // 新增：中心点到相机的实时距离（单位：米）

//   /* 采样参数 */
//   final int thetaSteps = 18;
//   final int phiSteps = 9;
//   final double radius = 0.5;
//   final double centerDist = 0.3 ; // 中心点距离校准时刻相机的距离（固定）
  
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

//     arSessionManager.onInitialize(
//       showAnimatedGuide: false,
//       showFeaturePoints: false,
//       showPlanes: true,
//       showWorldOrigin: true,
//     );

//     // 帧循环：仅在校准后执行采样、姿态传递、距离计算
//     _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
//       // 1. 实时计算中心点到相机的距离（核心新增）
//       if (isCalibrated && fixedCenter3D != null) {
//         final camPose = await arSessionManager.getCameraPose();
//         if (camPose != null) {
//           _calculateCenterToCameraDistance(camPose);
//           print("Mylog: centerPose: $fixedCenter3D, campos: ${camPose.getColumn(3)}");
//         }
        
//       }

//       // 2. 采样逻辑（原有）
//       if (scanning && isCalibrated && fixedCenter3D != null) {
//         await _onFrameSample();
//       }
      
//       // 3. 姿态传递逻辑（原有）
//       if (isCalibrated && initialCalibrationPose != null) {
//         final camPose = await arSessionManager.getCameraPose();
//         if (camPose != null && _isWebViewLoaded) {
//           // final relativePose = _calculateRelativePose(initialCalibrationPose!, camPose);
//           _sendPoseToWebView(camPose);
//         }
//       }
//     });
//   }

//   /* 新增：计算中心点到相机的实时距离 */
//   void _calculateCenterToCameraDistance(Matrix4 camPose) {
//     if (fixedCenter3D == null) return;
    
//     // 1. 获取当前相机的3D位置（从相机姿态矩阵中提取）
//     final camPos = camPose.getColumn(3).xyz; // 相机位置（世界坐标系）
//     camPos.z = -camPos.z;
//     // 2. 计算相机位置到固定中心点的直线距离（欧几里得距离）
//     // 公式：distance = √[(x2-x1)² + (y2-y1)² + (z2-z1)²]
//     final distance = (fixedCenter3D! - camPos).length;
    
//     // 3. 更新状态（保留2位小数，避免频繁刷新UI）
//     if (mounted && (distance - _centerToCameraDistance).abs() > 0.01) {
//       setState(() {
//         _centerToCameraDistance = double.parse(distance.toStringAsFixed(2));
//       });
//     }
//   }


//   /* 校准触发：计算并固定3D中心点 */
//   void _triggerCalibration() async {
//     final currentPose = await arSessionManager.getCameraPose();
//     if (currentPose != null) {
//       // 计算校准时刻的中心点（相机正前方centerDist处），并固定
//       final center = _calculateCalibrationCenter(currentPose);
//       // 校准时刻初始化距离（相机到中心点的初始距离=centerDist）
//       _centerToCameraDistance = centerDist;
      
//       setState(() {
//         initialCalibrationPose = currentPose;
//         isCalibrated = true;
//         fixedCenter3D = center; // 保存固定中心点（核心）
//       });
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('校准成功！中心点已固定'),
//           backgroundColor: Colors.green,
//           duration: Duration(seconds: 1),
//         ),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('校准失败，请重试'),
//           backgroundColor: Colors.red,
//           duration: Duration(seconds: 1),
//         ),
//       );
//     }
//   }

//   /* 计算校准时刻的中心点（仅执行一次） */
//   vm.Vector3 _calculateCalibrationCenter(Matrix4 camPose) {
//     final camPos = camPose.getColumn(3).xyz; // 校准时刻相机位置
//     final camForward = camPose.getColumn(2).xyz; // 相机前向（修正方向）
//     return camPos + camForward * centerDist; // 固定中心点 = 相机位置 + 前向×距离
//   }

//   /* 计算相对姿态 */
//   Matrix4 _calculateRelativePose(Matrix4 initialPose, Matrix4 currentPose) {
//     return Matrix4.tryInvert(initialPose)! * currentPose;
//   }

//   // 控制相机视角
//   void _sendPoseToWebView(Matrix4 camPose) {
//     if (fixedCenter3D == null) return; // 未校准则不传递

//     // 1. 计算手机（相机）相对于固定点的位置向量
//     final camPos = camPose.getColumn(3).xyz; // 相机位置（世界坐标系）
//     // camPos.z = -camPos.z; // 修正z轴方向（AR坐标系与Three.js可能相反）
//     final relativePos = (camPos - fixedCenter3D!).normalized()!; // 相机 - 固定点（得到相对位置）

//     // 2. 将相对位置转换为球面坐标（θ：方位角，φ：俯仰角）
//     final r = relativePos.length; // 距离（可不传，仅需角度）
//     final theta = atan2(relativePos.z, relativePos.x); // 方位角（绕y轴，-π~π）
//     final phi = atan2(relativePos.y, sqrt(relativePos.x*relativePos.x + relativePos.z*relativePos.z)); // 俯仰角（绕x轴，-π/2~π/2）
//     // final phi = asin(relativePos.y / r);
//     // 3. 转换为角度（便于HTML处理），并调整方向（使视角同步）
//     final thetaDeg = theta * 180 / pi; // 方位角（度）
//     final phiDeg = phi * 180 / pi; // 俯仰角（度）

//     // 4. 传递给HTML：控制小球的相机旋转到对应角度
//     _webViewController.runJavaScript(
//       'updateSphereView($thetaDeg, $phiDeg)' // 调用HTML的视角更新方法
//     );
//   }

//   /* 核心修复：计算当前视场内的圆点索引（基于固定中心点） */
//   (List<int>, List<int>) _currentCells(Matrix4 camPose) {
//     // 仅在校准后执行（固定中心点存在）
//     if (fixedCenter3D == null) return ([], []);

//     final camPos = camPose.getColumn(3).xyz; // 当前相机位置
//     // camPos.z = -camPos.z;
//     final dir = (fixedCenter3D! - camPos).normalized(); // 从当前相机指向固定中心点的方向

//     // phi角度计算（-π/2=北极，π/2=南极）
//     final phi = atan2(dir.y, sqrt(dir.x* dir.x + dir.z * dir.z)); 

//     // theta角度计算（横向角度：-π~π）
//     final theta = atan2(dir.z, dir.x); 

//     // phi索引映射（0=南极，4=赤道，8=北极）
//     final centerPhiIdx = (( ((phi + pi/2) / pi) * phiSteps).round())
//         .clamp(0, phiSteps - 1);
        
//     // theta索引映射（横向0~17）
//     final centerThetaIdx = (((theta + pi) / (2 * pi)) * thetaSteps).round()
//         .clamp(0, thetaSteps - 1);

//     // 检测范围（可根据需求调整）
//     const phiRange = 1; // 纵向检测范围：中心索引±1行
//     const thetaRange = 2; // 横向检测范围：中心索引±2列

//     // 有效索引范围（避免越界）
//     final minPhiIdx = (centerPhiIdx - phiRange).clamp(0, phiSteps - 1);
//     final maxPhiIdx = (centerPhiIdx + phiRange).clamp(0, phiSteps - 1);
//     final minThetaIdx = (centerThetaIdx - thetaRange).clamp(0, thetaSteps - 1);
//     final maxThetaIdx = (centerThetaIdx + thetaRange).clamp(0, thetaSteps - 1);

//     // 收集索引
//     final List<int> phiIndices = [];
//     final List<int> thetaIndices = [];
//     for (int p = minPhiIdx; p <= maxPhiIdx; p++) phiIndices.add(p);
//     for (int t = minThetaIdx; t <= maxThetaIdx; t++) thetaIndices.add(t);

//     return (phiIndices, thetaIndices);
//   }


//   /* 帧采样逻辑（仅在校准后执行） */
//   Future<void> _onFrameSample() async {
//     if (!isCalibrated || fixedCenter3D == null) return; // 未校准则不采样
    
//     final pose = await arSessionManager.getCameraPose();
//     if (pose == null) return;
    
//     final (phiIndices, thetaIndices) = _currentCells(pose);
    
//     for (final phiIdx in phiIndices) {
//       for (final thetaIdx in thetaIndices) {
//         final sampleKey = '$phiIdx\_$thetaIdx';
//         if (!sampledKeys.contains(sampleKey)) {
//           sampledIndices.add([phiIdx, thetaIdx]);
//           sampledKeys.add(sampleKey);

//           // 保存采样数据
//           final poseFile = File('${saveDir.path}/$sampleKey.json');
//           await poseFile.writeAsString(jsonEncode(pose.storage.toList()));

//           // 刷新UI
//           setState(() {});

//           // 通知HTML
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
//           content: Text('请先校准，固定中心点后再开始采样'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//       return;
//     }
//     setState(() => scanning = !scanning);
//   }

//   /* 清除逻辑（重置固定中心点） */
//   Future<void> _clear() async {
//     setState(() {
//       scanning = false;
//       sampledIndices.clear();
//       sampledKeys.clear();
//       isCalibrated = false;
//       initialCalibrationPose = null;
//       fixedCenter3D = null; 
//       _centerToCameraDistance = 0.0; // 清除距离显示
//     });
//     await saveDir.delete(recursive: true);
//     saveDir.createSync(recursive: true);
//     if (_isWebViewLoaded) {
//       _webViewController.runJavaScript('clearAllSamples()');
//     }
    
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('采样数据已清除，中心点已重置')),
//     );
//   }

//   @override
//   void dispose() {
//     _frameTimer?.cancel();
//     super.dispose();
//   }

//   /* UI布局：新增距离显示 */
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('3D 固定中心点采样'),
//         actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _clear)],
//         backgroundColor: Colors.red,
//       ),
//       body: Stack(
//         children: [
//           // AR相机预览
//           ARView(
//             onARViewCreated: onARViewCreated,
//             planeDetectionConfig: PlaneDetectionConfig.horizontal,
//           ),

//           // 中心准星（校准用）
//           Center(
//             child: Container(
//               width: 50,
//               height: 50,
//               decoration: BoxDecoration(
//                 border: Border.all(color: Colors.red, width: 2),
//                 borderRadius: BorderRadius.circular(25),
//               ),
//             ),
//           ),

//           // 右上角：WebView小球 + 校准按钮 + 进度 + 距离显示（新增）
//           Align(
//             alignment: Alignment.topRight,
//             child: Padding(
//               padding: const EdgeInsets.all(20),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // WebView小球（无旋转）
//                   SizedBox(
//                     width: 180,
//                     height: 180,
//                     child: WebViewWidget(controller: _webViewController),
//                   ),
//                   const SizedBox(height: 8),
                  
//                   // 校准状态提示
//                   isCalibrated 
//                       ? const Text('已校准（中心点固定）', style: TextStyle(color: Colors.green))
//                       : ElevatedButton(
//                           style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
//                           onPressed: _triggerCalibration,
//                           child: const Text('校准', style: TextStyle(color: Colors.white)),
//                         ),
//                   const SizedBox(height: 4),
                  
//                   // 新增：实时距离显示（黑色半透明背景，白色文字）
//                   if (isCalibrated)
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: Colors.black54,
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//                       child: Text(
//                         '距离：${_centerToCameraDistance} 米',
//                         style: const TextStyle(color: Colors.white, fontSize: 12),
//                       ),
//                     ),
//                   const SizedBox(height: 4),
                  
//                   // 采样进度
//                   Text(
//                     '${sampledIndices.length} / $totalCells',
//                     style: const TextStyle(
//                       color: Colors.white,
//                       backgroundColor: Colors.black54,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),

//           // 底部采样按钮（未校准则提示）
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: Padding(
//               padding: const EdgeInsets.only(bottom: 40),
//               child: ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: isCalibrated ? Colors.red : Colors.grey,
//                   padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
//                 ),
//                 onPressed: _toggleScan,
//                 child: Text(
//                   scanning ? '停止采样' : '开始采样',
//                   style: const TextStyle(fontSize: 16, color: Colors.white),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }