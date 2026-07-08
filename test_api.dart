import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://viewsys.co.in/api/player/login');
  
  print('Testing with no device_id...');
  var res = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({}));
  print('No device_id status: ${res.statusCode}, body: ${res.body}');

  print('Testing with dummy device_id...');
  res = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'device_id': '1234567899876544'}));
  print('Dummy device_id status: ${res.statusCode}, body: ${res.body}');
}
