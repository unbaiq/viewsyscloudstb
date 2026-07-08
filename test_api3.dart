import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';

void main() async {
  final url = Uri.parse('https://viewsys.co.in/api/player/register');
  
  final randCode = List.generate(16, (index) => Random().nextInt(10)).join();
  var res = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'device_id': randCode}));
  print('Register device_id status: ${res.statusCode}, body: ${res.body}');
}
