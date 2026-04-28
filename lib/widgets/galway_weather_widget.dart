import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GalwayWeatherWidget extends StatefulWidget {
  const GalwayWeatherWidget({super.key});

  @override
  State<GalwayWeatherWidget> createState() => _GalwayWeatherWidgetState();
}

class _GalwayWeatherWidgetState extends State<GalwayWeatherWidget> {
  bool _isLoading = true;
  String _temperature = '--';
  String _condition = 'Loading...';
  IconData _weatherIcon = Icons.cloud;
  Color _iconColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=53.2707&longitude=-9.0568&current_weather=true&timezone=Europe/Dublin');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final temp = current['temperature'].toString();
        final code = current['weathercode'] as int;

        _parseWeatherCode(code, temp);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _condition = 'Weather offline';
          _isLoading = false;
        });
      }
    }
  }

  void _parseWeatherCode(int code, String temp) {
    String condition;
    IconData icon;
    Color color;

    // WMO Weather interpretation codes
    if (code == 0) {
      condition = 'Clear Sky';
      icon = Icons.wb_sunny_rounded;
      color = Colors.orangeAccent;
    } else if (code == 1 || code == 2) {
      condition = 'Partly Cloudy';
      icon = Icons.cloud_queue_rounded;
      color = Colors.lightBlue;
    } else if (code == 3) {
      condition = 'Overcast';
      icon = Icons.cloud_rounded;
      color = Colors.grey;
    } else if (code >= 45 && code <= 48) {
      condition = 'Foggy';
      icon = Icons.foggy;
      color = Colors.blueGrey;
    } else if (code >= 51 && code <= 55) {
      condition = 'Drizzle';
      icon = Icons.grain;
      color = Colors.blue;
    } else if (code >= 61 && code <= 65) {
      condition = 'Rain';
      icon = Icons.water_drop_rounded;
      color = Colors.blueAccent;
    } else if (code >= 80 && code <= 82) {
      condition = 'Showers';
      icon = Icons.umbrella_rounded;
      color = Colors.indigoAccent;
    } else if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
      condition = 'Snow';
      icon = Icons.ac_unit_rounded;
      color = Colors.lightBlueAccent;
    } else if (code >= 95) {
      condition = 'Thunderstorm';
      icon = Icons.flash_on_rounded;
      color = Colors.deepPurpleAccent;
    } else {
      condition = 'Variable';
      icon = Icons.cloud_queue_rounded;
      color = Colors.grey;
    }

    if (mounted) {
      setState(() {
        _temperature = temp;
        _condition = condition;
        _weatherIcon = icon;
        _iconColor = color;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _iconColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_weatherIcon, color: _iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Galway Weather',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isLoading ? 'Fetching data...' : _condition,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!_isLoading && _temperature != '--')
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _temperature,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const Text(
                  '°C',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
