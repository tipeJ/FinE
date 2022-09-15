import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:fine/resources/resources.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:xml/xml.dart' as xml;

// Provider
class StatisticsProvider extends ChangeNotifier {
  List<_TimeSeriesEnergy> energy_production = [];
  List<_TimeSeriesEnergy> energy_consumption = [];

  Future<List> fetchProduction() async {
    final headers = {
      'x_api-key': fingrid_api_key,
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final params = {
      'start_time': _format_datetime(DateTime.now().subtract(const Duration(days: 1))),
      'end_time': _format_datetime(DateTime.now()),
    };
    final response = await http.get(Uri.https(fingrid_api_url, '/v1/variable/$FIN_ENERGY_PRODUCTION/events/json', params), headers: headers);
    return jsonDecode(response.body);
  }

  Future<List> fetchConsumption() async {
    final headers = {
      'x_api-key': fingrid_api_key,
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    final params = {
      'start_time': _format_datetime(DateTime.now().subtract(const Duration(days: 1))),
      'end_time': _format_datetime(DateTime.now()),
    };
    final response = await http.get(Uri.https(fingrid_api_url, '/v1/variable/$FIN_ENERGY_CONSUMPTION/events/json', params), headers: headers);
    return jsonDecode(response.body);
  }

  Future<void> fetchProductionConsumption() async {
    energy_production = (await fetchProduction()).map((e) => _TimeSeriesEnergy(DateTime.parse(e['start_time']), e['value'])).toList();
    energy_consumption = (await fetchConsumption()).map((e) => _TimeSeriesEnergy(DateTime.parse(e['start_time']), e['value'])).toList();
    notifyListeners();
  }

  String _format_datetime(DateTime time) {
    // Return in YYYY-MM-DDTHH:MM:SSZ format
    return '${time.toIso8601String().substring(0, 19)}Z';
  }
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MaterialButton(
          child: Text("Press me!"),
          onPressed: ()  {
            Provider.of<StatisticsProvider>(context, listen: false).fetchProductionConsumption();
          },
        ),
        Container(
          height: 400,
          child: Consumer<StatisticsProvider>(
            builder: (_, p, __) => p.energy_production.isEmpty ? Icon(Icons.help) : charts.TimeSeriesChart(
            [
              charts.Series<_TimeSeriesEnergy, DateTime>(
                id: 'Production',
                colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
                domainFn: (_TimeSeriesEnergy energy, _) => energy.time,
                measureFn: (_TimeSeriesEnergy energy, _) => energy.value,
                data: p.energy_production,
              ),
              charts.Series<_TimeSeriesEnergy, DateTime>(
                id: 'Consumption',
                colorFn: (_, __) => charts.MaterialPalette.red.shadeDefault,
                domainFn: (_TimeSeriesEnergy energy, _) => energy.time,
                measureFn: (_TimeSeriesEnergy energy, _) => energy.value,
                data: p.energy_consumption,
              ),
            ],
            animate: true,
            // defaultRenderer: charts.LineRendererConfig(includeArea: true, stacked: true),
            defaultRenderer: charts.LineRendererConfig(),
            defaultInteractions: true,
            behaviors: [
              charts.ChartTitle('Time', behaviorPosition: charts.BehaviorPosition.bottom, titleOutsideJustification: charts.OutsideJustification.middleDrawArea),
              charts.ChartTitle('Energy', behaviorPosition: charts.BehaviorPosition.start, titleOutsideJustification: charts.OutsideJustification.middleDrawArea),
            ],
          )
          ),
        ),
      ],
    );
  }
}

class _TimeSeriesEnergy {
  final DateTime time;
  final int value;

  _TimeSeriesEnergy(this.time, this.value);
}