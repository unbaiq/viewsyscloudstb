import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';

void main() async {
  final endpoints = [
    '/api/player/login',
    '/api/player/register',
    '/api/player/create',
    '/api/player/init',
    '/api/device/register'
  ];

  for (final path in endpoints) {
    final url = Uri.parse('https://viewsys.co.in' + path);
    final randCode = List.generate(16, (index) => Random().nextInt(10)).join();
    try {
      var res = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'device_id': randCode}));
      print('POST ' + path + ' -> ' + res.statusCode.toString() + ': ' + (res.body.length > 50 ? res.body.substring(0, 50) + "..." : res.body));
    } catch(e) {
      print('POST ' + path + ' -> Error');
    }
  }
}
