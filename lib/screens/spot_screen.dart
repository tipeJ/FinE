import 'package:flutter/material.dart';
import 'package:fine/resources/resources.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tuple/tuple.dart';
import 'dart:math';

class PriceProvider extends ChangeNotifier {
  List<Tuple2<DateTime, double>> day_prices = [];
  List<Tuple2<DateTime, double>> ahead_prices = [];
  DateTime? periodStart;
  DateTime? periodEnd;
  DateTime? periodNow;
  double? currentSpot;
  double? maxValue;
  double? minValue;

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
          DateTime.now().subtract(const Duration(days: 1))),
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
    // Reset time
    periodNow = DateTime.now().toUtc();

    // Reset max and min values
    maxValue = 0;
    minValue = double.maxFinite;
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
      // Get price.amount from points
      for (var point in points) {
        var price = convert_eur_MWH_to_cent_kWH(
            double.parse(point.findElements('price.amount').first.text));
        late DateTime pointStart;
        if (day_prices.isEmpty) {
          pointStart = periodStart!;
        } else if (ahead_prices.isEmpty) {
          pointStart = day_prices.last.item1.add(const Duration(minutes: 60));
        } else {
          pointStart = ahead_prices.last.item1.add(const Duration(minutes: 60));
        }
        if (pointStart.isBefore(periodNow!)) {
          day_prices.add(Tuple2(pointStart, price));
        } else {
          // We need to connect the two graphs together by adding the first point of ahead prices to day prices.
          if (ahead_prices.isEmpty) {
            day_prices.add(Tuple2(pointStart, price));
          }
          ahead_prices.add(Tuple2(pointStart, price));
        }
        if (price > maxValue!) {
          maxValue = price;
        }
        if (price < minValue!) {
          minValue = price;
        }
      }
    }
    currentSpot = ahead_prices.first.item2;
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

  String format_period_span(DateTime start, DateTime end) {
    // If the period is within the same day, show only the day
    if (start.day == end.day) {
      return start.day.toString() + '.' + start.month.toString();
    } else {
      var startString = start.day.toString() + '.' + start.month.toString();
      var endString = end.day.toString() + '.' + end.month.toString();
      return startString + ' - ' + endString;
    }
  }
}

class SpotScreen extends StatelessWidget {
  const SpotScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<PriceProvider>(builder: (_, p, __) {
      if (p.day_prices.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      } else {
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.all(25.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: Container(
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
                          top: 20.0, left: 35.0, right: 35.0),
                      child: _getLineChart(p),
                    ),
                    _getPriceIndicator(context, p)
                  ],
                ),
              ),
            ),
          ),
          // Indicator for highest price
          SliverToBoxAdapter(
            child: Card(
              color: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: Container(
                // padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Highest price'),
                        Text(
                          'Today',
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                    Text(
                      p.maxValue!.toStringAsFixed(2) + ' c/kWh',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 20.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]);
      }
    });
  }

  Widget _sideTitleWidget(PriceProvider p, double value, TitleMeta meta) {
    late DateTime item;
    int index = value.toInt();
    // Emit the first and last items
    if (index == 0 ||
        index >= p.day_prices.length + p.ahead_prices.length - 2) {
      return const SizedBox();
    }
    if (index < p.day_prices.length - 1) {
      item = p.day_prices[index].item1;
    } else if (index == p.day_prices.length - 1) {
      item = p.ahead_prices[0].item1;
    } else if (index < p.day_prices.length + p.ahead_prices.length - 1) {
      item = p.ahead_prices[index - p.day_prices.length + 1].item1;
    } else {
      return const SizedBox();
    }
    // Create MM:SS string
    late Widget child;
    var textStyle = const TextStyle(
      fontWeight: FontWeight.w200,
      color: Colors.white70,
      fontSize: 12,
    );
    if (item == p.ahead_prices[0].item1) {
      textStyle = textStyle.apply(
          fontWeightDelta: 3, color: Colors.white, fontSizeDelta: 1);
    }
    if (item.hour == 0 && item.minute == 0) {
      child = Text(
        '${item.day.toString().padLeft(2, '0')}.${item.month.toString().padLeft(2, '0')}',
        style: textStyle.apply(fontWeightDelta: 2, color: Colors.white),
      );
    } else {
      child = Text(
        '${item.hour.toString().padLeft(2, '0')}:${item.minute.toString().padLeft(2, '0')}',
        style: textStyle,
      );
    }
    return SideTitleWidget(axisSide: meta.axisSide, child: child);
  }

  Align _getPriceIndicator(BuildContext context, PriceProvider p) {
    return Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: EdgeInsets.only(
              left: min(MediaQuery.of(context).size.width / 20.0, 35.0),
              top: min(MediaQuery.of(context).size.width / 20.0, 35.0)),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: (p.currentSpot ?? 0.0).toStringAsFixed(2),
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium!
                        .apply(color: Colors.white, fontWeightDelta: 2)),
                TextSpan(
                    text: 'c/kWh',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.apply(color: Colors.white, fontWeightDelta: -2)),
              ])),
              Text(p.format_period_span(p.periodStart!, p.periodEnd!),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.apply(color: Colors.white70)),
            ],
          ),
        ));
  }

  LineChart _getLineChart(PriceProvider p) {
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(enabled: true),
        gridData: FlGridData(show: false, drawHorizontalLine: false),
        titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(
                axisNameSize: 16,
                sideTitles: SideTitles(
                    showTitles: true,
                    // interval: 2,
                    getTitlesWidget: ((value, meta) =>
                        _sideTitleWidget(p, value, meta))))),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (p.day_prices.length + p.ahead_prices.length).toDouble() - 2,
        minY: -2,
        maxY: (p.maxValue ?? 50.0) * 1.75,
        lineBarsData: [
          LineChartBarData(
            spots: p.day_prices
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.item2))
                .toList(),
            isCurved: true,
            color: Colors.white,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: Colors.white.withOpacity(0.1)),
          ),
          LineChartBarData(
              spots: p.ahead_prices
                  .asMap()
                  .entries
                  .map((e) => FlSpot(
                      p.day_prices.length.toDouble() - 1 + e.key.toDouble(),
                      e.value.item2))
                  .toList(),
              isCurved: true,
              color: Colors.white,
              barWidth: 3.5,
              dashArray: [10, 10],
              isStrokeCapRound: true,
              dotData: FlDotData(
                  show: true,
                  getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(
                      radius: 7,
                      color: Colors.blue.shade600,
                      strokeWidth: 3,
                      strokeColor: Colors.white),
                  checkToShowDot: (spot, barData) =>
                      spot.x.toInt() == p.day_prices.length - 1),
              belowBarData: BarAreaData(show: false)),
        ],
      ),
    );
  }
}
