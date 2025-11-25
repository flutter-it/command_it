import 'package:flutter/material.dart';

import 'weather_manager.dart';

class WeatherListView extends StatelessWidget {
  final List<WeatherEntry> data;
  WeatherListView(this.data);
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (BuildContext context, int index) {
        final entry = data[index];
        return ListTile(
          title: Text('${entry.cityName}, ${entry.country}'),
          subtitle: Text(entry.description),
          leading: Text(
            entry.icon,
            style: TextStyle(fontSize: 32),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${entry.temperature.toStringAsFixed(1)}°C'),
              Text('${entry.wind.toStringAsFixed(1)} km/h'),
            ],
          ),
        );
      },
    );
  }
}
