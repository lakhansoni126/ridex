import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WeatherData {
  final double temperature;
  final String condition;
  
  WeatherData({required this.temperature, required this.condition});
}

class WeatherService {
  static Future<WeatherData?> fetchWeather(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true'
      );
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final currentWeather = data['current_weather'];
        final temp = currentWeather['temperature'] as double;
        final weatherCode = currentWeather['weathercode'] as int;
        
        return WeatherData(
          temperature: temp,
          condition: _mapWeatherCodeToString(weatherCode),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching weather: $e');
      }
    }
    return null;
  }

  static String _mapWeatherCodeToString(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1 || code == 2 || code == 3) return 'Partly cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Unknown';
  }
}
