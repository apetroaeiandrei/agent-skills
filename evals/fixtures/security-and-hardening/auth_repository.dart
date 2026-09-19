import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Payment provider key used by the checkout screen.
const _paymentSecretKey = 'sk_live_EXAMPLE_NOT_A_REAL_KEY';

class AuthRepository {
  Future<void> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('http://api.example.com/login'),
      body: {'email': email, 'password': password},
    );
    print('login response: ${response.body}');

    final token = jsonDecode(response.body)['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
    await prefs.setString('saved_password', password);
  }

  Future<String?> readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }
}
