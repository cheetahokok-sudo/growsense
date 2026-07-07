import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../theme.dart';
import 'placeholder_screen.dart';
import 'today_screen.dart';

/// 5-tab shell: Today | Food | Activity | Analytics | Medical —
/// same order and naming as the PWA's bottom tab bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.appState});
  final AppState appState;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.appState.loadChildren();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      TodayScreen(appState: widget.appState),
      const PlaceholderScreen(
          title: 'Food', note: 'Food library — coming to Flutter next.'),
      const PlaceholderScreen(
          title: 'Activity', note: 'Activity browser — coming to Flutter.'),
      const PlaceholderScreen(
          title: 'Analytics', note: 'Trends & percentiles — coming to Flutter.'),
      const PlaceholderScreen(
          title: 'Medical', note: 'Growth measurements — coming to Flutter.'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('GrowSense',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 20, color: GsColors.text2),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              widget.appState.reset();
            },
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.today_outlined), label: 'Today'),
          BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_outlined), label: 'Food'),
          BottomNavigationBarItem(
              icon: Icon(Icons.directions_run_outlined), label: 'Activity'),
          BottomNavigationBarItem(
              icon: Icon(Icons.insights_outlined), label: 'Analytics'),
          BottomNavigationBarItem(
              icon: Icon(Icons.medical_information_outlined),
              label: 'Medical'),
        ],
      ),
    );
  }
}
