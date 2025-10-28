import 'dart:convert';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 保留：用于系统文件管理器选择
import 'package:image_picker/image_picker.dart'; // 新增：专门用于唤起相册/相机
import 'package:permission_handler/permission_handler.dart'; // 权限管理


void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3dgs应用',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _hasPermission = true;
  final List<String> _supportedVideoExtensions = ['mp4', 'mov', 'avi', 'flv', 'mkv'];
  // 新增：初始化image_picker（专门用于操作相册）
  final ImagePicker _imagePicker = ImagePicker();


  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      
      // 2. 禁用 WebView 自带的滚动，避免与 Vue 页面滚动冲突（导致遮罩层错位）
      ..setVerticalScrollBarEnabled(false)
      ..setHorizontalScrollBarEnabled(false)

      ..loadFlutterAsset('dist/index.html')
      ..addJavaScriptChannel(
        "FlutterFileChannel",
        onMessageReceived: (message) {
          print("收到 Vue3 消息：${message.message}");
          if (message.message != '') {
            print("打开文件系统");
            _openSystemFilePicker();
          }
        },
      )
      ..addJavaScriptChannel(
        'FlutterVideoChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          print("收到视频选择请求：${message.message}");
          if (message.message == 'selectVideoBySystem') {
            await _openVideoFilePickerBySystem(); // 系统文件管理器（不变）
          } else if (message.message == 'selectVideoByGallery') {
            await _openVideoPickerByGallery(); // 唤起相册（核心修改）
          }
        },
      );
  }

  // 权限申请：适配相册权限（核心调整：区分Android/iOS相册权限）
  Future<bool> _requestStoragePermission() async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      // Android 13+ 相册权限用 PHOTO_LIBRARY，旧版本用 READ_EXTERNAL_STORAGE
      status = await Permission.photos.request();
    } else {
      // iOS 相册统一用 PHOTO_LIBRARY
      status = await Permission.photos.request();
    }

    if (status.isGranted) {
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("需要相册权限才能选择视频，请在设置中开启")),
        );
      }
      return false;
    }
  }

  // 系统文件管理器选择视频（不变）
  Future<void> _openVideoFilePickerBySystem() async {
    if (!_hasPermission && !await _requestStoragePermission()) {
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedVideoExtensions,
        allowCompression: false,
        withData: false,
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;
        await _readVideoFileToBase64(filePath, fileName);
      } else {
        print("用户取消视频选择");
        _sendMessageToVue('videoPickerCancelled', '用户取消了视频选择');
      }
    } catch (e) {
      print('视频选择失败：${e.toString()}');
      _sendMessageToVue('videoPickerError', '视频选择失败：${e.toString()}');
    }
  }

  // 【核心修改】唤起系统相册，并筛选仅显示视频
  Future<void> _openVideoPickerByGallery() async {
    if (!_hasPermission && !await _requestStoragePermission()) {
      return;
    }

    try {
      // 1. 调用image_picker的pickVideo方法：直接唤起相册，且仅返回视频
      // source: ImageSource.gallery → 明确指定“从相册选择”（不是文件管理器）
      // maxDuration: Duration(minutes: 10) → 可选：限制选择视频的最大时长
      XFile? pickedVideo = await _imagePicker.pickVideo(
        source: ImageSource.gallery, // 核心参数：唤起相册（而非文件管理器）
        maxDuration: const Duration(minutes: 10), // 可选：限制视频时长（按需调整）
      );

      // 2. 处理选择结果（与原逻辑对齐）
      if (pickedVideo != null) {
        String filePath = pickedVideo.path; // 相册视频的本地路径
        String fileName = pickedVideo.name; // 视频文件名（含后缀）
        
        // 可选：二次筛选后缀（确保是支持的视频格式）
        String fileExt = fileName.split('.').last.toLowerCase();
        if (_supportedVideoExtensions.contains(fileExt)) {
          await _readVideoFileToBase64(filePath, fileName);
        } else {
          _sendMessageToVue('videoPickerError', '所选文件不是支持的视频格式（仅支持${_supportedVideoExtensions.join(', ')}）');
        }
      } else {
        print("用户取消相册视频选择");
        _sendMessageToVue('videoPickerCancelled', '用户取消了视频选择');
      }
    } catch (e) {
      print('相册视频选择失败：${e.toString()}');
      _sendMessageToVue('videoPickerError', '视频选择失败：${e.toString()}');
    }
  }

  // 读取视频转Base64（不变）
  Future<void> _readVideoFileToBase64(String filePath, String fileName) async {
    try {
      File file = File(filePath);
      List<int> bytes = await file.readAsBytes();
      String base64Data = base64Encode(bytes);
      await _controller.runJavaScript(
        'window.receiveVideoData("$fileName", "$base64Data")',
      );
    } catch (e) {
      await _controller.runJavaScript(
        'window.receiveVideoError("读取视频失败：${e.toString()}")',
      );
    }
  }

  // 现有文件选择逻辑（不变）
  Future<void> _openSystemFilePicker() async {
    if (!_hasPermission && !await _requestStoragePermission()) {
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowCompression: false,
        withData: false,
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;
        await _readFileFromPath(filePath, fileName);
      } else {
        print("用户取消了文件选择");
        _sendMessageToVue('filePickerCancelled', '用户取消了文件选择');
      }
    } catch (e) {
      print('文件选择失败：${e.toString()}');
      _sendMessageToVue('filePickerError', '文件选择失败：${e.toString()}');
    }
  }

  // 现有文件读取逻辑（不变）
  Future<void> _readFileFromPath(String filePath, String fileName) async {
    try {
      File file = File(filePath);
      List<int> bytes = await file.readAsBytes();
      String base64Data = base64Encode(bytes);
      await _controller.runJavaScript(
        'window.receiveFileData("$fileName", "$base64Data")',
      );
    } catch (e) {
      await _controller.runJavaScript(
        'window.receiveFileError("读取文件失败：${e.toString()}")',
      );
    }
  }

  // 向Vue发送消息（不变）
  Future<void> _sendMessageToVue(String type, String msg) async {
    await _controller.runJavaScript(
      'window.receiveFlutterMsg("$type", "$msg")',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: (_hasPermission)
          ? WebViewWidget(controller: _controller)
          : const Center(child: CircularProgressIndicator()),
    );
  }
}