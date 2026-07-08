import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';

void main() async {
  final url = Uri.parse('https://viewsys.co.in/api/player/login');
  
  final randCode = List.generate(16, (index) => Random().nextInt(10)).join();
  print('Trying device_id: $randCode');
  var res = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({
    'device_id': randCode,
    'device_type': 'android',
    'app_version': '1.0'
  }));
  print('Status: ${res.statusCode}, body: ${res.body}');
}
