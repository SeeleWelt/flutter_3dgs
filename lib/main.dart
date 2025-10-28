import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import "package:flutter_test1/custom_camera_page.dart";

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
        "FlutterFileSaveChannel",
        onMessageReceived: (JavaScriptMessage message) async {
          try {
              Map<String, dynamic> fileInfo = jsonDecode(message.message);
              print("开始保存文件：${fileInfo['fileName']}");

              // 解析Base64数据（去掉前缀 "data:video/mp4;base64,"）
              String base64Str = fileInfo['base64String'];
              String pureBase64 = base64Str.split(',').last; // 提取纯Base64部分
              Uint8List videoBytes = base64Decode(pureBase64); // 解码为字节数组

              Directory? saveDir;
              if (Platform.isAndroid) {
                saveDir = Directory('/storage/emulated/0/Download');
              } else if (Platform.isIOS) {
                saveDir = await getApplicationDocumentsDirectory();
              }

              if (saveDir == null) {
                print("无法获取存储路径");
                return;
              }

              String savePath = '${saveDir.path}/test-${fileInfo['fileName']}';
              await Directory(saveDir.path).create(recursive: true); // 递归创建目录

              File saveFile = File(savePath);
              await saveFile.writeAsBytes(videoBytes);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("已经保存到: $savePath")),
              );
            } catch (e) {
              print("保存视频失败：$e");
            }
        },
      )
      ..addJavaScriptChannel(
        'FlutterVideosChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          print("收到视频选择请求：${message.message}");
          if (message.message == 'selectVideosByGallery')
          {
            await _openVideoPickerByGallery(); // 系统文件管理器
          }
          else if (message.message == 'selectVideosByCamera')
          {
            await _openVideoPickerByCamera(); 
          }
          else if(message.message.startsWith('{"action":"save"'))
          {
            try {
              Map<String, dynamic> videoInfo = jsonDecode(message.message);
              print("开始保存视频：${videoInfo['name']}");

              // 解析Base64数据（去掉前缀 "data:video/mp4;base64,"）
              String base64Str = videoInfo['base64'];
              String pureBase64 = base64Str.split(',').last; // 提取纯Base64部分
              Uint8List videoBytes = base64Decode(pureBase64); // 解码为字节数组

              Directory? saveDir;
              if (Platform.isAndroid) {
                // saveDir = await getExternalStorageDirectory(); // 应用私有外部存储
                // 如需公共目录（如Download），需申请权限：
                saveDir = Directory('/storage/emulated/0/Download');
              } else if (Platform.isIOS) {
                saveDir = await getApplicationDocumentsDirectory();
              }

              if (saveDir == null) {
                print("无法获取存储路径");
                return;
              }

              String savePath = '${saveDir.path}/test-${videoInfo['name']}';
              await Directory(saveDir.path).create(recursive: true); // 递归创建目录

              File saveFile = File(savePath);
              await saveFile.writeAsBytes(videoBytes);

              print("模型保存成功：$savePath");
            } catch (e) {
              print("保存视频失败：$e");
            }
          }
        },
      );
  }

  // 权限申请：适配相册权限
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

  Future<void> _openVideoPickerByGallery() async {
    // 权限检查
    if (!_hasPermission && !await _requestStoragePermission()) {
      return;
    }

    try {
      // 调用多视频选择（修正参数语法）
      List<XFile> pickedVideos = await _imagePicker.pickMultiVideo(
        maxDuration: const Duration(minutes: 10), // 正确的参数写法
      );
      if(pickedVideos.isEmpty)
      {
        await _controller.runJavaScript(
        'window.receiveMultipleVideos("")');
      }
      // 处理选择结果
      else if (pickedVideos.isNotEmpty) {
        // 存储有效视频
        List<Map<String, String>> validVideos = [];

        // 遍历所有选中的视频
        for (var video in pickedVideos) {
          String filePath = video.path; // 视频本地路径
          String fileName = video.name; // 视频文件名
          
          // 筛选支持的视频格式
          String fileExt = fileName.split('.').last.toLowerCase();
          if (_supportedVideoExtensions.contains(fileExt)) {
            validVideos.add({
              'path': filePath,
              'name': fileName
            });
          } else {
            // 提示不支持的格式
            _sendMessageToVue(
              'videoPickerWarning', 
              '跳过不支持的格式：$fileName（仅支持${_supportedVideoExtensions.join(', ')}）'
            );
          }
        }

        // 如果有有效视频，批量处理
        if (validVideos.isNotEmpty) {
          await _batchProcessVideos(validVideos);
        } else {
          _sendMessageToVue(
            'videoPickerError', 
            '没有有效的视频文件（仅支持${_supportedVideoExtensions.join(', ')}）'
          );
        }
      } else {
        // 用户取消选择
        print("用户取消相册视频选择");
      }
    } catch (e) {
      // 错误处理
      print('相册视频选择失败：${e.toString()}');
    }
  }

  Future<void> _openVideoPickerByCamera() async {
    // 1. 申请相机+麦克风权限（录制视频需要）
    if (!await _requestCameraPermission()) {
      return;
    }
    
    // 3. 打开自定义摄像头页面，传入名称和录制完成回调
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SphereScanPage(
          onRecordComplete: (videoFile) async {
            // 4. 录制完成：处理视频（转Base64传给前端）
            await _processCustomCameraVideo(videoFile);
          },
        ),
      ),
    );
  }

  // 新增：相机权限申请
  Future<bool> _requestCameraPermission() async {
    PermissionStatus status = await Permission.camera.request();
    
    if (status.isGranted) {
      // 相机权限已授予，同时检查麦克风权限（如果需要录制音频）
      if (await Permission.microphone.isDenied) {
        await Permission.microphone.request();
      }
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("需要相机权限才能拍摄视频，请在设置中开启")),
        );
      }
      return false;
    }
  }

  // 新增：处理相机拍摄的视频（转Base64并发送给前端）
  Future<void> _processCustomCameraVideo(File videoFile) async {
    try {
      // 读取视频文件字节
      List<int> bytes = await videoFile.readAsBytes();
      String base64Data = base64Encode(bytes);
      String fileName = videoFile.path.split('/').last; // 获取带自定义名称的文件名

      // 构建与相册选择一致的数据格式（前端无需修改）
      List<Map<String, String>> videoDataList = [
        {
          'fileName': fileName,
          'base64Data': base64Data,
        }
      ];

      // 转JSON并发送给前端
      String jsonData = jsonEncode(videoDataList)
          .replaceAll('"', r'\"')
          .replaceAll('\n', '');

      await _controller.runJavaScript(
        'window.receiveMultipleVideos("$jsonData")',
      );

      // 可选：删除临时文件（避免占用存储，根据需求决定）
      // await videoFile.delete();
    } catch (e) {
      await _controller.runJavaScript(
        'window.receiveVideoError("处理拍摄视频失败：${e.toString()}")',
      );
    }
  }

  // 读取视频转Base64
  Future<void> _batchProcessVideos(List<Map<String, String>> videos) async {
    try {
      List<Map<String, String>> videoDataList = [];
      
      // 逐个读取视频（避免内存溢出）
      for (var video in videos) {
        File file = File(video['path']!);
        List<int> bytes = await file.readAsBytes();
        String base64Data = base64Encode(bytes);
        
        videoDataList.add({
          'fileName': video['name']!,
          'base64Data': base64Data
        });
      }

      // 转换为JSON并发送给前端
      String jsonData = jsonEncode(videoDataList)
          .replaceAll('"', r'\"')
          .replaceAll('\n', '');

      await _controller.runJavaScript(
        'window.receiveMultipleVideos("$jsonData")'
      );
    } catch (e) {
      await _controller.runJavaScript(
        'window.receiveVideoError("批量处理视频失败：${e.toString()}")'
      );
    }
  }


  // 向Vue发送消息
  Future<void> _sendMessageToVue(String type, String msg) async {
    await _controller.runJavaScript(
      'window.receiveFlutterMsg("$type", "$msg")',
    );
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    body: (_hasPermission)
        ? SafeArea(  // 包裹在 SafeArea 中，不包含状态栏
            child: WebViewWidget(controller: _controller),
          )
        : const Center(child: CircularProgressIndicator()),
        );
  }
}