import 'dart:convert';
import 'dart:io' show HttpException;

import 'package:command_it/command_it.dart';
import 'package:http/http.dart' as http;

import 'json/open_meteo_response.dart';

class WeatherManager {
  late Command<String?, List<WeatherEntry>> updateWeatherCommand;
  late Command<bool, bool> setExecutionStateCommand;
  late Command<String, String> textChangedCommand;

  WeatherManager() {
    Command.globalExceptionHandler = (_, __) {
      print('Global Exception Handler');
    };
    // Command expects a bool value when executed and sets it as its own value
    setExecutionStateCommand = Command.createSync<bool, bool>(
      (b) => b,
      initialValue: true,
    );

    // We pass the result of switchChangedCommand as canExecut to the upDateWeatherCommand
    updateWeatherCommand = Command.createAsync<String?, List<WeatherEntry>>(
      update, // Wrapped function
      initialValue: [], // Initial value
      /// as the switch is on when the command can be executed we need to invert the value
      /// to make the command disabled when the switch is off
      restriction: setExecutionStateCommand.map((switchState) => !switchState),
    );

    // Will be called on every change of the searchfield
    textChangedCommand = Command.createSync((s) => s, initialValue: '');

    // handler for results
    // make sure we start processing only if the user make a short pause typing
    textChangedCommand.debounce(Duration(milliseconds: 500)).listen((
      filterText,
      _,
    ) {
      // I could omit he execute because Command is a callable
      // class  but here it makes the intention clearer
      updateWeatherCommand.execute(filterText);
    });

    updateWeatherCommand.errors.listen((ex, _) => print(ex.toString()));

    // Update data on startup
    updateWeatherCommand.execute();
  }

  // Async function that queries the Open-Meteo API and converts the result into the form our ListViewBuilder can consume
  Future<List<WeatherEntry>> update(String? filtertext) async {
    // Build comma-separated latitude and longitude strings for all 50 cities
    final latitudes = topCities.map((c) => c.latitude).join(',');
    final longitudes = topCities.map((c) => c.longitude).join(',');

    // Open-Meteo API - no API key required!
    // Request current weather data for all cities in one call
    final url = 'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitudes'
        '&longitude=$longitudes'
        '&current=temperature_2m,relative_humidity_2m,rain,weather_code,wind_speed_10m';

    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

    // only continue if valid response
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch weather data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // Open-Meteo returns an array when querying multiple locations
    final jsonData = json.decode(response.body);
    final locationDataList = jsonData is List ? jsonData : [jsonData];

    // convert JSON result into a List of WeatherEntries
    // Zip the city names with the weather data (they're in the same order)
    final entries = <WeatherEntry>[];
    for (var i = 0; i < locationDataList.length && i < topCities.length; i++) {
      final city = topCities[i];
      final weatherData = OpenMeteoLocationWeather.fromJson(
        locationDataList[i] as Map<String, dynamic>,
      );
      entries.add(WeatherEntry.fromOpenMeteo(city, weatherData));
    }

    // Apply client-side filtering
    return entries
        .where(
          (entry) =>
              filtertext == null ||
              filtertext
                  .isEmpty || // if filtertext is null or empty we return all entries
              entry.cityName.toUpperCase().startsWith(
                    filtertext.toUpperCase(),
                  ),
        ) // otherwise only matching entries
        .toList();
  }
}

class WeatherEntry {
  final String cityName;
  final String country;
  final String? iconURL;
  final String icon;
  final double wind;
  final double rain;
  final double temperature;
  final String description;
  final int? humidity;

  WeatherEntry({
    required this.cityName,
    required this.country,
    this.iconURL,
    required this.icon,
    required this.wind,
    required this.rain,
    required this.temperature,
    required this.description,
    this.humidity,
  });

  factory WeatherEntry.fromOpenMeteo(
      TopCity city, OpenMeteoLocationWeather weather) {
    final wmoCode = weather.current.weather;
    return WeatherEntry(
      cityName: city.name,
      country: city.country,
      iconURL: null, // Open-Meteo doesn't provide icon URLs
      icon: wmoCode.icon,
      wind: weather.current.windSpeed,
      rain: weather.current.rain ?? 0.0,
      temperature: weather.current.temperature,
      description: wmoCode.description,
      humidity: weather.current.humidity,
    );
  }
}
