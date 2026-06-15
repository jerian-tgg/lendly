import 'dart:convert';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  static const String cloudName = 'dpnsayn8m'; // Your Cloudinary cloud name
  static const String uploadPreset = 'lendly_preset';

  static Future<String?> uploadImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return null;

    final io.File file = io.File(pickedFile.path);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    )
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final resBody = await http.Response.fromStream(response);
    final jsonData = json.decode(resBody.body);
    return jsonData['secure_url'];
  }
}
