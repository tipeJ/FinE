import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:fine/resources/resources.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:xml/xml.dart' as xml;
import 'package:fl_chart/fl_chart.dart';

// Provider
class StatisticsProvider extends ChangeNotifier {
  List<_TimeSeriesEnergy> energy_production = [];
  List<_TimeSeriesEnergy> energy_consumption = [];

  StatisticsProvider() {
    fetchProductionConsumption();
  }

  Future<List> fetchProduction() async {
    final headers = {
      'x_api-key': fingrid_api_key,
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final params = {
      'start_time':
          _format_datetime(DateTime.now().subtract(const Duration(days: 7))),
      'end_time': _format_datetime(DateTime.now()),
    };
    final response = await http.get(
        Uri.https(fingrid_api_url,
            '/v1/variable/$FIN_ENERGY_PRODUCTION/events/json', params),
        headers: headers);
    return jsonDecode(response.body);
  }

  Future<List> fetchConsumption() async {
    final headers = {
      'x_api-key': fingrid_api_key,
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final params = {
      'start_time':
          _format_datetime(DateTime.now().subtract(const Duration(days: 7))),
      'end_time': _format_datetime(DateTime.now()),
    };
    final response = await http.get(
        Uri.https(fingrid_api_url,
            '/v1/variable/$FIN_ENERGY_CONSUMPTION/events/json', params),
        headers: headers);
    return jsonDecode(response.body);
  }

  Future<void> fetchProductionConsumption() async {
    energy_production = (await fetchProduction())
        .map((e) =>
            _TimeSeriesEnergy(DateTime.parse(e['start_time']), e['value']))
        .toList();
    energy_consumption = (await fetchConsumption())
        .map((e) =>
            _TimeSeriesEnergy(DateTime.parse(e['start_time']), e['value']))
        .toList();
    notifyListeners();
  }

  // Get minimum values for energy production and consumption
  int get min_production => energy_production
      .map((e) => e.value)
      .reduce((value, element) => value < element ? value : element);
  int get min_consumption => energy_consumption
      .map((e) => e.value)
      .reduce((value, element) => value < element ? value : element);

  String _format_datetime(DateTime time) {
    // Return in YYYY-MM-DDTHH:MM:SSZ format
    return '${time.toIso8601String().substring(0, 19)}Z';
  }
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({Key? key}) : super(key: key);
  static const _listItemMargin =
      EdgeInsets.only(left: 25.0, right: 25.0, top: 25.0);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Title
        SliverToBoxAdapter(
          child: Container(
            margin: _listItemMargin,
            child: Text(
              'Last week',
              style: Theme.of(context).textTheme.headline4,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Card(
            margin: _listItemMargin,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            clipBehavior: Clip.antiAlias,
            child: Consumer<StatisticsProvider>(
              builder: (_, p, __) => p.energy_production.isEmpty
                  ? Icon(Icons.help)
                  : Container(
                      height: 400.0,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.blue.shade400, Colors.blue.shade700],
                      )),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 15.0, left: 15.0, right: 15.0),
                            child: _getProductionConsumptionChart(p),
                          ),
                          _currentValueDetails(p)
                        ],
                      )),
            ),
          ),
        )
      ],
    );
  }

  Widget _currentValueDetails(StatisticsProvider p) {
    final production = p.energy_production.last.value;
    final consumption = p.energy_consumption.last.value;
    final diff = production - consumption;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(15.0),
        decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Production now'),
                Text('${production.toStringAsFixed(2)} MW',
                    style: const TextStyle(color: Colors.greenAccent)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Consumption now'),
                Text('${consumption.toStringAsFixed(2)} MW',
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Difference now'),
                Text('${diff.toStringAsFixed(2)} MW',
                    style: TextStyle(
                        color:
                            diff > 0 ? Colors.greenAccent : Colors.redAccent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LineChart _getProductionConsumptionChart(StatisticsProvider p) {
    return LineChart(
      p.energy_production.isEmpty
          ? LineChartData()
          : LineChartData(
              lineBarsData: [
                LineChartBarData(
                    color: Colors.greenAccent,
                    dotData: FlDotData(show: false),
                    spots: p.energy_production
                        .asMap()
                        .entries
                        .map((e) =>
                            FlSpot(e.key.toDouble(), e.value.value.toDouble()))
                        .toList()),
                LineChartBarData(
                    color: Colors.redAccent,
                    dotData: FlDotData(show: false),
                    spots: p.energy_consumption
                        .asMap()
                        .entries
                        .map((e) =>
                            FlSpot(e.key.toDouble(), e.value.value.toDouble()))
                        .toList()),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.blue.shade700,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final flSpot = spot;
                      if (flSpot.x == 0) {
                        return LineTooltipItem(
                          '0',
                          const TextStyle(color: Colors.white),
                        );
                      }
                      return LineTooltipItem(
                        '${flSpot.y}',
                        const TextStyle(color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: false,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.white,
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.white,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                  show: true,
                  topTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          interval: p.energy_production.length / 7,
                          getTitlesWidget: (value, meta) =>
                              _getSideTitlesWidget(value, meta, p))),
                  bottomTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false))),
              borderData: FlBorderData(
                show: false,
              ),
              minY: min(p.min_consumption, p.min_production) / 1.25,
            ),
    );
  }

  Widget _getSideTitlesWidget(
      double value, TitleMeta meta, StatisticsProvider p) {
    // Get corresponding DateTime
    int index = value.toInt();
    if (index == p.energy_production.length - 1) {
      return const SizedBox();
    }
    final time = p.energy_production[index].time;
    // Return a date indicator
    return Text(
      '${time.day}.${time.month}',
      style: TextStyle(color: Colors.white),
    );
  }
}

class _TimeSeriesEnergy {
  final DateTime time;
  final int value;

  _TimeSeriesEnergy(this.time, this.value);
}
