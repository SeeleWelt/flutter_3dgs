// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:path_provider/path_provider.dart';

// class CustomCameraPage extends StatefulWidget {
//   final String videoName;
//   final Function(File) onRecordComplete;

//   const CustomCameraPage({
//     super.key,
//     required this.videoName,
//     required this.onRecordComplete,
//   });

//   @override
//   State<CustomCameraPage> createState() => _CustomCameraPageState();
// }

// class _CustomCameraPageState extends State<CustomCameraPage> {
//   late List<CameraDescription> _cameras;
//   late CameraController _controller;
//   bool _isControllerReady = false;
//   XFile? _recordedVideo;
//   bool _isRecording = false;
//   int _recordDuration = 0;
//   Timer? _recordTimer;

//   @override
//   void initState() {
//     super.initState();
//     // 隐藏系统状态栏实现全屏
//     SystemChrome.setEnabledSystemUIMode(
//       SystemUiMode.immersiveSticky,
//       overlays: [],
//     );
//     _initCamera();
//   }

//   Future<void> _initCamera() async {
//     try {
//       _cameras = await availableCameras();
//       // 优先选择后置摄像头
//       CameraDescription rearCamera = _cameras.firstWhere(
//         (cam) => cam.lensDirection == CameraLensDirection.back,
//         orElse: () => _cameras.first,
//       );

//       // 获取设备屏幕尺寸
//       final size = MediaQuery.of(context).size;
//       // 计算屏幕宽高比
//       final screenAspectRatio = size.width / size.height;

//       // 选择与屏幕比例最接近的分辨率（保持原始画面比例）
//       ResolutionPreset selectedPreset = ResolutionPreset.veryHigh;
      
//       _controller = CameraController(
//         rearCamera,
//         selectedPreset, // 使用选定的分辨率
//         enableAudio: true,
//         imageFormatGroup: ImageFormatGroup.yuv420,
//       );

//       await _controller.initialize();
//       if (mounted) {
//         setState(() => _isControllerReady = true);
//       }
//     } catch (e) {
//       print("相机初始化失败：$e");
//       if (mounted) Navigator.pop(context);
//     }
//   }

//   Future<void> _startRecording() async {
//     if (!_isControllerReady || !_controller.value.isInitialized || _isRecording) {
//       return;
//     }

//     try {
//       _recordDuration = 0;
//       _isRecording = true;
//       _recordedVideo = null;
//       setState(() {});

//       _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//         if (!mounted || !_isRecording) {
//           timer.cancel();
//           return;
//         }
//         setState(() => _recordDuration++);
//         if (_recordDuration >= 300) { // 最长录制5分钟
//           timer.cancel();
//           _stopRecording();
//         }
//       });

//       await _controller.startVideoRecording();
//     } catch (e) {
//       print("录制启动失败：$e");
//       _isRecording = false;
//       _recordTimer?.cancel();
//       setState(() {});
//     }
//   }

//   Future<void> _stopRecording() async {
//     if (!_isRecording || !_controller.value.isInitialized) return;

//     try {
//       _recordTimer?.cancel();
//       _isRecording = false;
//       XFile tempVideoFile = await _controller.stopVideoRecording();
//       setState(() {});

//       Directory appDocDir = await getApplicationDocumentsDirectory();
//       String saveDir = '${appDocDir.path}/custom_videos';
//       await Directory(saveDir).create(recursive: true);
//       String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
//       String customFileName = '${widget.videoName}_$timestamp.mp4';
//       String customVideoPath = '$saveDir/$customFileName';

//       File finalVideoFile = File(tempVideoFile.path);
//       await finalVideoFile.copy(customVideoPath);

//       widget.onRecordComplete(File(customVideoPath));

//       // 清理临时文件
//       try {
//         if (await finalVideoFile.exists()) await finalVideoFile.delete();
//         File tempFile = File(tempVideoFile.path);
//         if (await tempFile.exists()) await tempFile.delete();
//       } catch (e) {
//         print("删除视频文件失败：$e");
//       }
//       Navigator.pop(context);
//     } catch (e) {
//       print("录制停止/文件处理失败：$e");
//     }
//   }

//   String _formatDuration() {
//     int minutes = _recordDuration ~/ 60;
//     int seconds = _recordDuration % 60;
//     return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
//   }

//   @override
//   void dispose() {
//     // 恢复系统状态栏
//     SystemChrome.setEnabledSystemUIMode(
//       SystemUiMode.edgeToEdge,
//       overlays: SystemUiOverlay.values,
//     );
//     _controller.dispose();
//     _recordTimer?.cancel();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (!_isControllerReady) {
//       return const Scaffold(
//         backgroundColor: Colors.black,
//         body: Center(child: CircularProgressIndicator(color: Colors.white)),
//       );
//     }

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           // 全屏相机预览（关键优化）
//           Positioned.fill(
//             child: _buildCameraPreview(),
//           ),

//           // 顶部控制栏
//           Positioned(
//             top: MediaQuery.of(context).padding.top + 16,
//             left: 16,
//             right: 16,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 IconButton(
//                   icon: const Icon(Icons.close, color: Colors.white, size: 28),
//                   onPressed: () => Navigator.pop(context),
//                 ),
//                 if (_isRecording)
//                   Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                     decoration: BoxDecoration(
//                       color: Colors.red.withOpacity(0.8),
//                       borderRadius: BorderRadius.circular(4),
//                     ),
//                     child: Text(
//                       _formatDuration(),
//                       style: const TextStyle(color: Colors.white, fontSize: 16),
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           // 底部录制按钮
//           Positioned(
//             bottom: 30,
//             left: 0,
//             right: 0,
//             child: Center(
//               child: GestureDetector(
//                 onTap: _isRecording ? _stopRecording : _startRecording,
//                 child: Container(
//                   width: _isRecording ? 80 : 100,
//                   height: _isRecording ? 80 : 100,
//                   decoration: BoxDecoration(
//                     color: _isRecording ? Colors.red : Colors.white,
//                     shape: BoxShape.circle,
//                     border: _isRecording ? null : Border.all(color: Colors.white, width: 4),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // 构建全屏相机预览
//   Widget _buildCameraPreview() {
//     final size = MediaQuery.of(context).size;
//     final previewSize = _controller.value.previewSize!;

//     // 计算预览画面的缩放比例（保持原始比例充满屏幕）
//     final double previewRatio = previewSize.width / previewSize.height;
//     final double screenRatio = size.width / size.height;

//     double scale;
//     if (previewRatio > screenRatio) {
//       // 预览更宽，按高度缩放
//       scale = size.height / previewSize.height;
//     } else {
//       // 预览更高，按宽度缩放
//       scale = size.width / previewSize.width;
//     }

//     return Transform.scale(
//       scale: scale,
//       alignment: Alignment.center,
//       child: AspectRatio(
//         aspectRatio: previewRatio,
//         child: CameraPreview(_controller),
//       ),
//     );
//   }
// }