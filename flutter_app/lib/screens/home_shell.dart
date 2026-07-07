import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'activity_screen.dart';
import 'analytics_screen.dart';
import 'food_screen.dart';
import 'medical_screen.dart';
import 'today_screen.dart';

/// 5-tab shell: Today | Food | Activity | Analytics | Medical —
/// same order and naming as the PWA's bottom tab bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

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
    final t = widget.i18n.t;
    final screens = [
      TodayScreen(appState: widget.appState, i18n: widget.i18n),
      FoodScreen(appState: widget.appState, i18n: widget.i18n),
      ActivityScreen(appState: widget.appState, i18n: widget.i18n),
      AnalyticsScreen(appState: widget.appState, i18n: widget.i18n),
      MedicalScreen(appState: widget.appState, i18n: widget.i18n),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('GrowSense',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: GsColors.accentLight,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: t('flutter.language', 'Language'),
            icon: Icon(Icons.language,
                size: 20, color: Colors.white.withValues(alpha: 0.85)),
            onSelected: widget.i18n.setLanguage,
            itemBuilder: (context) => [
              for (final entry in supportedLanguages.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: widget.i18n.code == entry.key
                            ? const Icon(Icons.check,
                                size: 15, color: GsColors.accent)
                            : null,
                      ),
                      Text(entry.value,
                          style: const TextStyle(fontSize: 13.5)),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: t('flutter.sign_out', 'Sign out'),
            icon: Icon(Icons.logout,
                size: 20, color: Colors.white.withValues(alpha: 0.85)),
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
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.today_outlined),
              label: t('nav.today', 'Today')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.restaurant_outlined),
              label: t('flutter.nav.food', 'Food')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.directions_run_outlined),
              label: t('flutter.nav.activity', 'Activity')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.insights_outlined),
              label: t('nav.analytics', 'Analytics')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.medical_information_outlined),
              label: t('nav.medical', 'Medical')),
        ],
      ),
    );
  }
}
