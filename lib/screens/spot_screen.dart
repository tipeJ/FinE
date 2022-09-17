import 'package:flutter/material.dart';
import 'package:fine/resources/resources.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tuple/tuple.dart';

class PriceProvider extends ChangeNotifier {
  List<Tuple2<DateTime, double>> day_prices = [];
  DateTime? periodStart;
  DateTime? periodEnd;
  DateTime? periodNow;

  PriceProvider() {
    fetchSpot();
  }

  Future<void> fetchSpot() async {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final params = {
      'DocumentType': 'A44',
      'processType': 'A16',
      'securityToken': entsoe_api_key,
      'In_Domain': ENTSOE_AREA_FINLAND,
      'Out_Domain': ENTSOE_AREA_FINLAND,
      'periodStart': _format_datetime_entsoe(
          DateTime.now().subtract(const Duration(days: 0))),
      'periodEnd':
          _format_datetime_entsoe(DateTime.now().add(const Duration(days: 2))),
    };
    var response = await http.get(Uri.https(entsoe_api_url, '/api', params),
        headers: headers);
    // Parse XML
    var document = XmlDocument.parse(response.body);
    // Parse document
    var timeSeries = document.findAllElements('TimeSeries');
    // Get price measure unit
    var priceMeasureUnit =
        timeSeries.first.findElements('price_Measure_Unit.name').first.text;
    // Get price currency
    var priceCurrency =
        timeSeries.first.findElements('currency_Unit.name').first.text;
    day_prices = [];
    for (var ts in timeSeries) {
      // Find the period
      var period = ts.findElements('Period');
      // Find all points
      var points = period.first.findElements('Point');
      // Find time interval
      var timeInterval = period.first.findElements('timeInterval').first;
      // Find start
      var timeStart = timeInterval.findElements('start').first.text;
      periodStart = DateTime.parse(timeStart);
      // Find end
      var timeEnd = timeInterval.findElements('end').first.text;
      periodEnd = DateTime.parse(timeEnd);
      // Reset time
      periodNow = DateTime.now();
      // Get price.amount from points
      for (var point in points) {
        var price = convert_eur_MWH_to_cent_kWH(
            double.parse(point.findElements('price.amount').first.text));
        late DateTime pointStart;
        if (day_prices.isEmpty) {
          pointStart = periodStart!;
        } else {
          pointStart = day_prices.last.item1.add(const Duration(minutes: 30));
        }
        day_prices.add(Tuple2(pointStart, price));
      }
    }
    notifyListeners();
  }

  String _format_datetime_entsoe(DateTime time) {
    // Return in YYYYMMDDHHMM format, rounding to the nearest hour
    return time.year.toString() +
        time.month.toString().padLeft(2, '0') +
        time.day.toString().padLeft(2, '0') +
        time.hour.toString().padLeft(2, '0') +
        '00';
  }

  double convert_eur_MWH_to_cent_kWH(double price) {
    return price / 1000 * 100;
  }
}

class SpotScreen extends StatelessWidget {
  const SpotScreen({Key? key}) : super(key: key);

  Widget _sideTitleWidget(PriceProvider p, double value, TitleMeta meta) {
    int index = value.toInt();
    if (index >= p.day_prices.length) {
      return const SizedBox();
    }
    final item = p.day_prices[value.toInt()].item1;
    return SideTitleWidget(
        axisSide: meta.axisSide, child: Text("${item.hour}:${item.minute}"));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PriceProvider>(builder: (_, p, __) {
      if (p.day_prices.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      } else {
        return LineChart(
          LineChartData(
            lineTouchData: LineTouchData(enabled: true),
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(
                show: true,
                topTitles: AxisTitles(
                    axisNameSize: 16,
                    sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: ((value, meta) =>
                            _sideTitleWidget(p, value, meta))))),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: p.day_prices.length.toDouble(),
            minY: 0,
            lineBarsData: [
              LineChartBarData(
                spots: p.day_prices
                    .asMap()
                    .entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value.item2))
                    .toList(),
                isCurved: true,
                color: Colors.blue,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(show: true),
                belowBarData: BarAreaData(
                    show: true, color: Colors.blue.withOpacity(0.3)),
              ),
            ],
          ),
        );
      }
    });
  }
}
