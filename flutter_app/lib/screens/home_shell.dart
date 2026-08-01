import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_logo.dart';
import 'account_screen.dart';
import 'activity_screen.dart';
import 'analytics_screen.dart';
import 'coach_screen.dart';
import 'food_scan_sheets.dart';
import 'food_screen.dart';
import 'medical_modules.dart';
import 'medical_screen.dart';
import 'today_screen.dart';

/// App shell. Bottom bar: Today | Analytics | ⊕ | Coach | Medical —
/// the center ⊕ opens the quick-log sheet (Bevel-style action grid),
/// which is where Food and Activity now live as pushed screens.
/// Top bar: original GrowSense logo, language menu, avatar → Account.
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
    // Children are already loaded by RootGate (the onboarding gate that
    // renders this shell); only units remain to fetch here.
    widget.appState.loadUnits();
  }

  void _push(Widget body, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          body: body,
        ),
      ),
    );
  }

  void _quickLog(String action) {
    final t = widget.i18n.t;
    switch (action) {
      case 'food':
        _push(
          FoodScreen(appState: widget.appState, i18n: widget.i18n),
          t('flutter.nav.food', 'Food'),
        );
      case 'activity':
        _push(
          ActivityScreen(appState: widget.appState, i18n: widget.i18n),
          t('flutter.nav.activity', 'Activity'),
        );
      case 'sleep':
        setState(() => _tab = 0);
      case 'measurement':
        _push(
          MeasurementsScreen(appState: widget.appState, i18n: widget.i18n),
          t('flutter.growth_measurements', 'Growth measurements'),
        );
      case 'illness':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                IllnessLogScreen(appState: widget.appState, i18n: widget.i18n),
          ),
        );
      case 'labs':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                LabResultsScreen(appState: widget.appState, i18n: widget.i18n),
          ),
        );
      case 'scan_meal':
        startMealScan(context, widget.appState, widget.i18n);
      case 'scan_label':
        startLabelScan(context, widget.appState, widget.i18n);
    }
  }

  void _openQuickLogSheet() {
    final t = widget.i18n.t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        void go(String action) {
          Navigator.pop(sheetContext);
          _quickLog(action);
        }

        return Container(
          decoration: const BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grab handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: GsColors.border2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 14),
                    child: Text(
                      t('flutter.quick_log', 'Quick log'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _QuickTile(
                        emoji: '🍗',
                        label: t('flutter.log_food', 'Log food'),
                        tint: GsColors.accent,
                        onTap: () => go('food'),
                      ),
                      const SizedBox(width: 12),
                      _QuickTile(
                        emoji: '🏃',
                        label: t('flutter.log_activity', 'Log activity'),
                        tint: GsColors.measured,
                        onTap: () => go('activity'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Food Lens — camera-first logging (premium; the flows
                  // show the paywall sheet themselves when locked).
                  Row(
                    children: [
                      _QuickTile(
                        emoji: '📸',
                        label: t('flutter.fscan.snap_meal', 'Snap a meal'),
                        tint: GsColors.accent,
                        onTap: () => go('scan_meal'),
                      ),
                      const SizedBox(width: 12),
                      _QuickTile(
                        emoji: '🏷️',
                        label: t('flutter.fscan.scan_label', 'Scan a nutrition label'),
                        tint: GsColors.estimated,
                        onTap: () => go('scan_label'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QuickTile(
                        emoji: '😴',
                        label: t('flutter.log_sleep', 'Log sleep'),
                        tint: GsColors.estimated,
                        onTap: () => go('sleep'),
                      ),
                      const SizedBox(width: 12),
                      _QuickTile(
                        emoji: '📏',
                        label: t('flutter.log_measurement', 'Log measurement'),
                        tint: GsColors.measured,
                        onTap: () => go('measurement'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QuickTile(
                        emoji: '🤒',
                        label: t('flutter.log_illness', 'Log illness'),
                        tint: GsColors.estimated,
                        onTap: () => go('illness'),
                      ),
                      const SizedBox(width: 12),
                      _QuickTile(
                        emoji: '🧪',
                        label: t('flutter.log_labs', 'Log lab result'),
                        tint: GsColors.flag,
                        onTap: () => go('labs'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final screens = [
      TodayScreen(
        appState: widget.appState,
        i18n: widget.i18n,
        onQuickLog: _quickLog,
      ),
      AnalyticsScreen(
        appState: widget.appState,
        i18n: widget.i18n,
        onCorrectDay: (date) {
          // Trust calendar "Correct this day": open that date in the
          // Today editors.
          widget.appState.setLogDate(date);
          setState(() => _tab = 0);
        },
      ),
      CoachScreen(appState: widget.appState, i18n: widget.i18n),
      MedicalScreen(appState: widget.appState, i18n: widget.i18n),
    ];

    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const GsLogo(),
        actions: [
          PopupMenuButton<String>(
            tooltip: t('flutter.language', 'Language'),
            icon: const Icon(Icons.language, size: 20, color: GsColors.text2),
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
                            ? const Icon(
                                Icons.check,
                                size: 15,
                                color: GsColors.accent,
                              )
                            : null,
                      ),
                      Text(entry.value, style: const TextStyle(fontSize: 13.5)),
                    ],
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountScreen(
                    appState: widget.appState,
                    i18n: widget.i18n,
                  ),
                ),
              ),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: GsColors.accent,
                child: Text(
                  email.isEmpty ? '?' : email.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: screens),
      // ⚠️ Height goes on the content INSIDE SafeArea, not on the outer
      // Container. With `height: 62` outside, the home-indicator inset
      // (~34pt on Face ID iPhones) was subtracted from the 62, leaving
      // ~28pt for a column that measures ~37pt — so the icons overflowed
      // upward and sat hard against the top border with no breathing
      // room. 54pt of content plus the inset matches the native iOS tab
      // bar and looks identical on devices with no inset at all.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: GsColors.surface,
          border: Border(top: BorderSide(color: GsColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.today_outlined,
                  label: t('nav.today', 'Today'),
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _NavItem(
                  icon: Icons.insights_outlined,
                  label: t('nav.analytics', 'Analytics'),
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                // Quick log lives at the same level as the tabs — a plain
                // item, just marked with a small filled accent circle.
                Expanded(
                  child: InkWell(
                    onTap: _openQuickLogSheet,
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: GsColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  icon: Icons.auto_awesome_outlined,
                  label: t('nav.ai_coach', 'AI coach'),
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
                _NavItem(
                  icon: Icons.medical_information_outlined,
                  label: t('nav.medical', 'Medical'),
                  selected: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GsColors.accent : GsColors.text3;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern quick-log tile — soft tinted card, gradient icon bubble,
/// large tap target, gentle press-scale.
class _QuickTile extends StatefulWidget {
  const _QuickTile({
    required this.emoji,
    required this.label,
    required this.tint,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  widget.tint.withValues(alpha: 0.10),
                  widget.tint.withValues(alpha: 0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.tint.withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.tint.withValues(alpha: 0.22),
                        widget.tint.withValues(alpha: 0.10),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: GsColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
