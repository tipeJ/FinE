import 'package:flutter/material.dart';
import 'screens.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

enum _MainScreenTab { statistics, price, menu }
class _MainScreenState extends State<MainScreen> {
  _MainScreenTab _currentTab = _MainScreenTab.statistics;

  @override
  Widget build(BuildContext context) {
    // Scaffold with bottom navigation bar
    Widget child_screen;
    String title;
    switch (_currentTab) {
      case _MainScreenTab.statistics:
        child_screen = const StatisticsScreen();
        title = 'Statistics';
        break;
      default:
        child_screen = const SpotScreen();
        title = 'Spot Price';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: child_screen,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: 'Statistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.euro),
            label: 'Price',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
        currentIndex: _MainScreenTab.values.indexOf(_currentTab),
        selectedItemColor: Colors.amber[800],
        onTap: (int index) {
          setState(() {
            _currentTab = _MainScreenTab.values[index];
          });
        },
      ),
    );
  }
}