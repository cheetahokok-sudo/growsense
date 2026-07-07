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
import 'food_screen.dart';
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
    widget.appState.loadChildren();
  }

  void _push(Widget body, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: body,
      ),
    ));
  }

  void _quickLog(String action) {
    final t = widget.i18n.t;
    switch (action) {
      case 'food':
        _push(FoodScreen(appState: widget.appState, i18n: widget.i18n),
            t('flutter.nav.food', 'Food'));
      case 'activity':
        _push(ActivityScreen(appState: widget.appState, i18n: widget.i18n),
            t('flutter.nav.activity', 'Activity'));
      case 'sleep':
        setState(() => _tab = 0);
      case 'measurement':
        setState(() => _tab = 3);
    }
  }

  void _openQuickLogSheet() {
    final t = widget.i18n.t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GsRadius.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('flutter.quick_log', 'Quick log'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _QuickAction(
                    emoji: '🍗',
                    label: t('flutter.log_food', 'Log food'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _quickLog('food');
                    },
                  ),
                  _QuickAction(
                    emoji: '🏀',
                    label: t('flutter.log_activity', 'Log activity'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _quickLog('activity');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _QuickAction(
                    emoji: '😴',
                    label: t('flutter.log_sleep', 'Log sleep'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _quickLog('sleep');
                    },
                  ),
                  _QuickAction(
                    emoji: '📏',
                    label: t('flutter.log_measurement', 'Log measurement'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _quickLog('measurement');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final screens = [
      TodayScreen(appState: widget.appState, i18n: widget.i18n),
      AnalyticsScreen(appState: widget.appState, i18n: widget.i18n),
      CoachScreen(
          appState: widget.appState,
          i18n: widget.i18n,
          onQuickLog: _quickLog),
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
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AccountScreen(
                    appState: widget.appState, i18n: widget.i18n),
              )),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: GsColors.accent,
                child: Text(
                  email.isEmpty ? '?' : email.characters.first.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: Container(
        height: 62,
        decoration: const BoxDecoration(
          color: GsColors.surface,
          border: Border(top: BorderSide(color: GsColors.border)),
        ),
        child: SafeArea(
          top: false,
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
                      child: const Icon(Icons.add,
                          size: 20, color: Colors.white),
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
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
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
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.emoji, required this.label, required this.onTap});
  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: GsColors.surface2,
              borderRadius: BorderRadius.circular(GsRadius.md),
            ),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: GsColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: gsShadow,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
