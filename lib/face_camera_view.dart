import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于加载资源文件
import 'package:flutter/foundation.dart'; // 用于 WriteBuffer
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCameraView extends StatefulWidget {
  const FaceCameraView({super.key});

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView>
    with SingleTickerProviderStateMixin {
  late CameraController _cameraController; // 摄像头控制器
  late FaceDetector _faceDetector; // 人脸检测器
  late AnimationController _animationController; // 动画控制器
  List<Face> _faces = []; // 检测到的人脸列表
  bool _isDetecting = false; // 是否正在检测
  ui.Image? _catFaceImage; // 猫脸图片
  Size? _imageSize; // 摄像头图像的尺寸
  bool _hasError = false; // 是否发生错误
  bool _isCameraInitialized = false; // 摄像头是否初始化完成
  Offset? _tapPosition; // 点击位置
  double _catFaceOpacity = 1.0; // 猫脸图片透明度

  @override
  void initState() {
    super.initState();
    _initialize(); // 初始化摄像头和人脸检测器

    // 初始化动画控制器
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // 动画持续时间
    )..addListener(() {
      setState(() {}); // 动画更新时重绘
    });
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("No cameras found.");
        return;
      }

      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController.initialize();

      setState(() {
        _isCameraInitialized = true; // 摄像头初始化完成
      });

      // 初始化人脸检测器
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true, // 启用轮廓检测
          enableClassification: true, // 启用分类（如微笑检测）
          performanceMode: FaceDetectorMode.accurate, // 设置性能模式为高精度
        ),
      );

      // 加载猫脸图片
      final ByteData data = await rootBundle.load('assets/images/cat_face.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _catFaceImage = frame.image;

      // 开始摄像头图像流
      _cameraController.startImageStream((image) async {
        if (_isDetecting) return; // 如果正在检测，直接返回
        _isDetecting = true;

        try {
          // 处理摄像头图像并检测人脸
          final inputImage = _processCameraImage(image);
          final faces = await _faceDetector.processImage(inputImage);

          if (mounted) {
            setState(() {
              _faces = faces; // 更新检测到的人脸列表
              _imageSize = Size(
                image.width.toDouble(),
                image.height.toDouble(),
              ); // 更新图像尺寸
            });
          }
        } catch (e) {
          debugPrint("Detection error: $e"); // 打印检测错误日志
        } finally {
          _isDetecting = false; // 检测完成
        }
      });

      setState(() {}); // 更新 UI
    } catch (e) {
      debugPrint("Camera initialization error: $e"); // 打印初始化错误日志
      setState(() {
        _hasError = true; // 设置错误状态
      });
    }
  }

  // 处理摄像头图像为 ML Kit 可用的格式
  InputImage _processCameraImage(CameraImage image) {
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final bytes = allBytes.done().buffer.asUint8List();

    final inputImageMetadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()), // 图像尺寸
      rotation:
          InputImageRotationValue.fromRawValue(
            _cameraController.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg, // 图像旋转角度
      format:
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21, // 图像格式
      bytesPerRow: image.planes[0].bytesPerRow, // 每行字节数
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  @override
  void dispose() {
    _animationController.dispose(); // 释放动画控制器
    _cameraController.dispose(); // 释放摄像头资源
    _faceDetector.close(); // 关闭人脸检测器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || !_isCameraInitialized) {
      return Container(color: Colors.black);
    }

    if (!_cameraController.value.isInitialized || _imageSize == null) {
      return Container(
        color: Colors.black, // 全屏黑色背景
      );
    }

    return GestureDetector(
      onTapDown: (details) {
        // 获取点击位置
        setState(() {
          _tapPosition = details.localPosition;
        });

        // 重置动画并启动
        _animationController.reset();
        _animationController.forward();

        // 启动猫脸透明度动画
        _startCatFaceFadeOutAndRecover();
      },
      child: Stack(
        children: [
          // 黑色背景层
          Container(
            color: Colors.black, // 全屏黑色背景
          ),
          // 摄像头预览
          CameraPreview(_cameraController),
          // 自定义绘制层
          CustomPaint(
            size: Size.infinite, // 确保覆盖整个屏幕
            painter: FaceOverlayPainter(
              faceRects: _faces, // 检测到的人脸列表
              imageSize: _imageSize!, // 图像尺寸
              cameraLensDirection:
                  _cameraController.description.lensDirection, // 摄像头方向
              catFaceImage: _catFaceImage, // 猫脸图片
              tapPosition: _tapPosition, // 点击位置
              animationValue: _animationController.value, // 动画值
              catFaceOpacity: _catFaceOpacity, // 猫脸透明度
            ),
          ),
        ],
      ),
    );
  }

  void _startCatFaceFadeOutAndRecover() {
    setState(() {
      _catFaceOpacity = 1.0; // 重置透明度
    });

    // 启动一个 0.5 秒的动画逐渐消失
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _catFaceOpacity = 0.0; // 将透明度设置为 0
        });

        // 再启动一个 3 秒的动画逐渐恢复
        Future.delayed(Duration(milliseconds: 3000), () {
          if (mounted) {
            setState(() {
              _catFaceOpacity = 1.0; // 恢复透明度
            });
          }
        });
      }
    });
  }
}

class FaceOverlayPainter extends CustomPainter {
  final List<Face> faceRects; // 人脸列表
  final Size imageSize; // 图像尺寸
  final CameraLensDirection cameraLensDirection; // 摄像头方向
  final ui.Image? catFaceImage; // 猫脸图片
  final Offset? tapPosition; // 点击位置
  final double animationValue; // 动画值
  final double catFaceOpacity; // 猫脸透明度

  FaceOverlayPainter({
    required this.faceRects,
    required this.imageSize,
    required this.cameraLensDirection,
    this.catFaceImage,
    this.tapPosition,
    required this.animationValue,
    required this.catFaceOpacity, // 添加透明度参数
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style =
              PaintingStyle
                  .stroke // 设置绘制样式为描边
          ..strokeWidth =
              2.0 // 设置描边宽度
          ..color = Colors.greenAccent; // 设置描边颜色

    // 计算缩放比例
    double scaleX = size.width / imageSize.width;
    double scaleY = size.height / imageSize.height;

    // 使用相同的缩放比例，保持宽高比一致
    double scale = scaleX < scaleY ? scaleX : scaleY;

    for (final face in faceRects) {
      final faceRect = face.boundingBox; // 获取人脸边界框

      // 映射边界框到屏幕坐标
      Rect scaledRect = Rect.fromLTRB(
        faceRect.left * scale,
        faceRect.top * scale,
        faceRect.right * scale,
        faceRect.bottom * scale,
      );

      final center = Offset(
        scaledRect.left + scaledRect.width / 2,
        scaledRect.top + scaledRect.height / 2,
      );

      // 根据头部旋转角度调整水平偏移
      final double horizontalOffset =
          (cameraLensDirection == CameraLensDirection.front)
              ? -(face.headEulerAngleY ?? 0) *
                  0.5 // 反转前置摄像头方向
              : (face.headEulerAngleY ?? 0) * 0.5; // 后置摄像头方向保持不变

      // 保存当前 Canvas 状态
      canvas.save();

      // 将 Canvas 平移到中心点
      canvas.translate(center.dx + horizontalOffset, center.dy);

      // 根据头部旋转角度旋转 Canvas
      final double rotationAngle =
          (face.headEulerAngleZ ?? 0) * (3.141592653589793 / 180); // 转换为弧度
      canvas.rotate(-rotationAngle);

      // 绘制绿色框和猫脸图片
      final rotatedRect = Rect.fromCenter(
        center: Offset(0, 0),
        width: scaledRect.width,
        height: scaledRect.height,
      );
      canvas.drawRect(rotatedRect, paint);

      // 绘制猫脸图片
      if (catFaceImage != null && catFaceOpacity > 0) {
        final dstRect = Rect.fromCenter(
          center: Offset(0, 0),
          width: scaledRect.width * 1.6,
          height: scaledRect.height * 1.6,
        );

        // 设置透明度
        final paintWithOpacity =
            Paint()..color = Colors.white.withOpacity(catFaceOpacity);

        canvas.saveLayer(dstRect, paintWithOpacity); // 应用透明度
        paintImage(
          canvas: canvas,
          rect: dstRect,
          image: catFaceImage!,
          fit: BoxFit.cover,
        );
        canvas.restore();
      }

      // 恢复 Canvas 状态
      canvas.restore();
    }

    // 绘制点击动画效果
    if (tapPosition != null) {
      final animationPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = Colors.blue.withOpacity(1.0 - animationValue); // 动画渐隐

      final radius = 50.0 * animationValue; // 动画半径随时间变化
      canvas.drawCircle(tapPosition!, radius, animationPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 始终触发重绘
  }
}
