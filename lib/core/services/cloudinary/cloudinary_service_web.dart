import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const String cloudName = 'dpnsayn8m'; // Your Cloudinary cloud name
  static const String uploadPreset = 'lendly_preset';

  static Future<String?> uploadImage() async {
    final html.FileUploadInputElement input = html.FileUploadInputElement()
      ..accept = 'image/*';
    input.click();

    final completer = Completer<String?>();

    input.onChange.listen((event) async {
      final file = input.files?.first;
      if (file == null) {
        completer.complete(null);
        return;
      }

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final data = reader.result as Uint8List;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
      )
        ..fields['upload_preset'] = uploadPreset
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          data,
          filename: file.name,
        ));

      final response = await request.send();
      final resBody = await http.Response.fromStream(response);
      final jsonData = json.decode(resBody.body);
      completer.complete(jsonData['secure_url']);
    });

    return completer.future;
  }
}
