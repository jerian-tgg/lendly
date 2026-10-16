import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class DocumentUploadService {
  static const String cloudName = 'dpnsayn8m';
  static const String uploadPreset = 'lendly_preset';

  static final ImagePicker _picker = ImagePicker();

  /// Pick an image from Camera
  static Future<XFile?> pickImageFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1600,
      );
      return file;
    } catch (e) {
      return null;
    }
  }

  /// Pick an image from Gallery
  static Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
      );
      return file;
    } catch (e) {
      return null;
    }
  }

  /// Pick multiple images from Gallery
  static Future<List<XFile>> pickMultipleImages() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
      );
      return files;
    } catch (e) {
      return [];
    }
  }

  /// Upload an XFile (works cross-platform on web, mobile, desktop) to Cloudinary
  static Future<String> uploadXFile(XFile file) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final bytes = await file.readAsBytes();

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'bir_permit_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      final url = jsonData['secure_url'];
      if (url != null && url is String) {
        return url;
      }
      throw Exception('Secure URL not found in Cloudinary response');
    } else {
      throw Exception('Cloudinary upload failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Upload a list of XFiles and return their URLs
  static Future<List<String>> uploadMultipleXFiles(List<XFile> files) async {
    final List<String> urls = [];
    for (final file in files) {
      final url = await uploadXFile(file);
      urls.add(url);
    }
    return urls;
  }
}
