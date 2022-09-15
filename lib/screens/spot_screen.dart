import 'package:flutter/material.dart';
import 'package:fine/resources/resources.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

class PriceProvider extends ChangeNotifier {
  List<double> day_prices = [];
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
      // 'processType': 'A16',
      'processType': 'A16',
      'securityToken': entsoe_api_key,
      'In_Domain': ENTSOE_AREA_FINLAND,
      'Out_Domain': ENTSOE_AREA_FINLAND,
      'periodStart': _format_datetime_entsoe(DateTime.now().subtract(const Duration(days: 7))),
      'periodEnd': _format_datetime_entsoe(DateTime.now().subtract(const Duration(days: 1))),
    };
    params['periodStart'] = "202209160000";
    params['periodEnd'] = "202209170000";
    // var qurl = "https://" + entsoe_api_url + "/api?" + "securityToken=$entsoe_api_key&documentType=A44&in_Domain=$ENTSOE_AREA_FINLAND&out_Domain=$ENTSOE_AREA_FINLAND&periodStart=201512312300&periodEnd=201612312300";
    // var response = await http.get(Uri.parse(qurl), headers: headers);
    var response = await http.get(Uri.https(entsoe_api_url, '/api', params), headers: headers);
    // Parse XML
    var document = XmlDocument.parse(response.body);
    // Parse document
    var timeSeries = document.findAllElements('TimeSeries');
    // Find the period
    var period = timeSeries.first.findElements('Period');
    // Find all points
    var points = period.first.findElements('Point');
    // Get price.amount from points
    var prices = points.map((e) => double.parse(e.findElements('price.amount').first.text)).toList();
    day_prices = prices;
    notifyListeners();
  }

  String _format_datetime_entsoe(DateTime time) {
    // Return in YYYYMMDDHHMM format
    return '${time.year}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}';
  }
}
class SpotScreen extends StatelessWidget {
  const SpotScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return 
        Consumer<PriceProvider>(
            builder: (_, p, __) => p.day_prices.isEmpty ? Icon(Icons.help) : LineChart(
              LineChartData(
                lineTouchData: LineTouchData(enabled: true),
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(show: false, topTitles: AxisTitles(axisNameSize: 16)),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 24,
                minY: 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: p.day_prices.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.3)),
                  ),
                ],
              ),
            ),
            );

  }
}