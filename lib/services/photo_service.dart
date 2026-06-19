import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

/// 照片管理服务
/// 负责照片的选取、保存、读取、删除
class PhotoService {
  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  final ImagePicker _picker = ImagePicker();

  /// 获取照片存储目录路径
  Future<Directory> getPhotoDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    return photoDir;
  }

  /// 从相册选择多张照片，返回保存后的文件名列表
  Future<List<String>> pickImagesFromGallery() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return _savePickedFiles(files);
  }

  /// 拍照，返回保存后的文件名
  Future<String?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (file == null) return null;
    final results = await _savePickedFiles([file]);
    return results.isNotEmpty ? results.first : null;
  }

  /// 保存选中的文件到本地照片目录
  Future<List<String>> _savePickedFiles(List<XFile> files) async {
    if (files.isEmpty) return [];
    final photoDir = await getPhotoDir();
    final savedNames = <String>[];

    for (final file in files) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final randomSuffix = (savedNames.length + 1);
        final fileName = 'photo_${timestamp}_$randomSuffix.jpg';
        final destPath = '${photoDir.path}/$fileName';

        if (kIsWeb) {
          // Web 平台：读取字节后写入
          final bytes = await file.readAsBytes();
          await File(destPath).writeAsBytes(bytes);
        } else {
          // 移动端/桌面：复制文件
          await File(file.path).copy(destPath);
        }
        savedNames.add(fileName);
      } catch (e) {
        debugPrint('保存照片失败：$e');
      }
    }
    return savedNames;
  }

  /// 根据文件名获取照片文件的完整路径
  Future<String?> getPhotoPath(String fileName) async {
    try {
      final photoDir = await getPhotoDir();
      final file = File('${photoDir.path}/$fileName');
      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      debugPrint('获取照片路径失败：$e');
      return null;
    }
  }

  /// 根据文件名读取照片文件的字节
  Future<Uint8List?> getPhotoBytes(String fileName) async {
    try {
      final path = await getPhotoPath(fileName);
      if (path != null) {
        return await File(path).readAsBytes();
      }
      return null;
    } catch (e) {
      debugPrint('读取照片失败：$e');
      return null;
    }
  }

  /// 删除单张照片
  Future<void> deletePhoto(String fileName) async {
    try {
      final path = await getPhotoPath(fileName);
      if (path != null) {
        await File(path).delete();
      }
    } catch (e) {
      debugPrint('删除照片失败：$e');
    }
  }

  /// 批量删除照片
  Future<void> deletePhotos(List<String> fileNames) async {
    for (final name in fileNames) {
      await deletePhoto(name);
    }
  }

  /// 复制照片到指定目录（用于导出）
  Future<bool> copyPhotoTo(String fileName, String destDirPath) async {
    try {
      final sourcePath = await getPhotoPath(fileName);
      if (sourcePath == null) return false;
      final destDir = Directory(destDirPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      await File(sourcePath).copy('${destDir.path}/$fileName');
      return true;
    } catch (e) {
      debugPrint('复制照片失败：$e');
      return false;
    }
  }
}
