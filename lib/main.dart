import 'package:flutter/material.dart';
import 'face_camera_view.dart';

void main() {
  runApp(const MyApp()); // 运行应用程序的入口
}

// 应用程序的根组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: FaceCameraView(), // 确保 FaceCameraView 占据整个屏幕
      ),
    );
  }
}
