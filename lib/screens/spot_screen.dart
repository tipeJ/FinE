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
  String? errorMesssage;

  Tuple2<DateTime, double> getMaxValue(List<Tuple2<DateTime, double>> prices) {
    return prices.reduce(
        (value, element) => value.item2 > element.item2 ? value : element);
  }

  Tuple2<DateTime, double> getMinValue(List<Tuple2<DateTime, double>> prices) {
    return prices.reduce(
        (value, element) => value.item2 < element.item2 ? value : element);
  }

  double getAverage(List<Tuple2<DateTime, double>> prices) {
    return prices.fold(0.0, (sum, element) => sum + element.item2) /
        prices.length;
  }

  String formatDay(DateTime date) {
    // If the date is today, return "Today"
    if (date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year) {
      return 'Today';
    }
    // If the date is tomorrow, return "Tomorrow"
    if (date.day == DateTime.now().day + 1 &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year) {
      return 'Tomorrow';
    }
    return '${date.day}.${date.month}';
  }

  Tuple2<DateTime, double> getSpotByIndex(int index) {
    if (index < day_prices.length) {
      return day_prices[index];
    } else {
      return ahead_prices[index - day_prices.length + 1];
    }
  }

  Tuple2<DateTime, DateTime> getPeakHours(
      List<Tuple2<DateTime, double>> prices) {
    // Get highest value
    final max = getMaxValue(prices);
    // Get top 75th percentile
    final top75 = prices
        .where((element) => element.item2 > max.item2 * 0.75)
        .toList()
        .first
        .item2
        .floor();
    // Get all values, on either side of the maximum value, that are above the top75
    // Iterate first to the left
    final left = prices
        .takeWhile((element) => element.item1.isBefore(max.item1))
        .where((element) => element.item2 > top75)
        .toList();
    final left_item = left.isNotEmpty ? left.first : max;
    // Then to the right
    final right = prices
        .skipWhile((element) => element.item1.isBefore(max.item1))
        .where((element) => element.item2 > top75)
        .toList();
    final right_item = right.isNotEmpty ? right.first : max;
    return Tuple2(left_item.item1, right_item.item1);
  }

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
    // Make timeout 10 seconds
    const timeout = Duration(seconds: 7);
    late http.Response response;
    try {
      response = await http
          .get(Uri.https(entsoe_api_url, '/api', params), headers: headers)
          .timeout(timeout, onTimeout: () {
        return http.Response('', 408);
      });
      if (response.statusCode != 200) {
        errorMesssage = 'Error ${response.statusCode}';
        notifyListeners();
        return;
      } else {
        errorMesssage = null;
      }
    } catch (e) {
      errorMesssage = 'Error: ${e.toString()}';
      notifyListeners();
      return;
    }
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
      periodStart = DateTime.parse(timeStart).toLocal();
      // Find end
      var timeEnd = timeInterval.findElements('end').first.text;
      periodEnd = DateTime.parse(timeEnd).toLocal();
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
  static const _listItemMargin =
      EdgeInsets.only(left: 25.0, right: 25.0, top: 25.0);

  @override
  Widget build(BuildContext context) {
    return Consumer<PriceProvider>(builder: (_, p, __) {
      if (p.errorMesssage != null) {
        return Center(
          child: Text(p.errorMesssage!),
        );
      } else if (p.day_prices.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      } else {
        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Card(
                margin: _listItemMargin,
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
                            top: 15.0, left: 15.0, right: 15.0),
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
              child: Container(
                margin: _listItemMargin,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(15.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Highest price',
                            style: Theme.of(context).textTheme.headline6),
                        Text(
                          'Next ${p.ahead_prices.length} hours',
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${p.getMaxValue(p.ahead_prices).item2.toStringAsFixed(2)} c/kWh',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20.0),
                        ),
                        Text(
                          p.getMaxValue(p.ahead_prices).item1.hour.toString() +
                              ':00 ' +
                              p.formatDay(p.getMaxValue(p.ahead_prices).item1),
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Indicator for lowest price
            SliverToBoxAdapter(
              child: Container(
                margin: _listItemMargin,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(15.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lowest price',
                            style: Theme.of(context).textTheme.headline6),
                        Text(
                          'Next ${p.ahead_prices.length} hours',
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${p.getMinValue(p.ahead_prices).item2.toStringAsFixed(2)} c/kWh',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20.0),
                        ),
                        Text(
                          p.getMinValue(p.ahead_prices).item1.hour.toString() +
                              ':00 ' +
                              p.formatDay(p.getMinValue(p.ahead_prices).item1),
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Average price
            SliverToBoxAdapter(
              child: Container(
                margin: _listItemMargin,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(15.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Average price',
                            style: Theme.of(context).textTheme.headline6),
                        Text(
                          'Next ${p.ahead_prices.length} hours',
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                    Text(
                      '${p.getAverage(p.ahead_prices).toStringAsFixed(2)} c/kWh',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 20.0),
                    ),
                  ],
                ),
              ),
            ),
            // Display peak hours
            SliverToBoxAdapter(
              child: Container(
                margin: _listItemMargin,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(15.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Peak hours',
                            style: Theme.of(context).textTheme.headline6),
                        Text(
                          'Next ${p.ahead_prices.length} hours',
                          style: Theme.of(context).textTheme.subtitle1,
                        )
                      ],
                    ),
                    _getPeakHoursIndicator(p, context),
                  ],
                ),
              ),
            ),
          ]),
        );
      }
    });
  }

  Column _getPeakHoursIndicator(PriceProvider p, BuildContext context) {
    final peakHours = p.getPeakHours(p.ahead_prices);
    String time_indicator = p.formatDay(peakHours.item1);
    if (peakHours.item1.day != peakHours.item2.day) {
      time_indicator =
          '${p.formatDay(peakHours.item1)} - ${p.formatDay(peakHours.item2)}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${peakHours.item1.hour.toString()}:00 - ${peakHours.item2.hour.toString()}:00',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20.0),
        ),
        Text(
          time_indicator,
          style: Theme.of(context).textTheme.subtitle1,
        )
      ],
    );
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
        lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                int index = spot.x.round();
                final s = p.getSpotByIndex(index);
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} c/kWh\n ${s.item1.hour.toString().padLeft(2, '0')}:${s.item1.minute.toString().padLeft(2, '0')}',
                  const TextStyle(color: Colors.white),
                );
              }).toList(),
            )),
        gridData: FlGridData(show: false, drawHorizontalLine: false),
        titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    interval: 25,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) =>
                        value == meta.max || value == meta.min
                            ? const SizedBox()
                            : Text(value.round().toString(),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)))),
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
            barWidth: 2.5,
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
              barWidth: 2.5,
              dashArray: [8, 3],
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
