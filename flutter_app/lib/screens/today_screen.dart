import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'today_hud.dart';

/// Today tab — read-only first pass: child switcher, date selector,
/// and the day's nutrition / sleep / activity as saved by the PWA.
/// Logging (writes) comes after the read path is proven.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.loadingChildren) {
          return const Center(child: CircularProgressIndicator());
        }
        if (appState.children.isEmpty) {
          return _EmptyNote(i18n.t('flutter.no_children'));
        }
        return RefreshIndicator(
          onRefresh: appState.loadDay,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _ChildSwitcher(appState: appState),
              const SizedBox(height: 12),
              _DateSelector(appState: appState, i18n: i18n),
              const SizedBox(height: 12),
              if (appState.lastError != null)
                _ErrorCard(message: appState.lastError!),
              if (appState.loadingDay)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ReadinessCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                ConsistencyCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                _NutritionCard(nutrition: appState.nutrition, i18n: i18n),
                const SizedBox(height: 12),
                _LoggedFoodCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                SleepEditorCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                _ActivityCard(
                    items: appState.activityItems,
                    appState: appState,
                    i18n: i18n),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Child switcher ──────────────────────────────────────────────────

class _ChildSwitcher extends StatelessWidget {
  const _ChildSwitcher({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: appState.children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = appState.children[i];
          final name = (c['name'] as String? ?? '?');
          final active = i == appState.activeChild;
          return GestureDetector(
            onTap: () => appState.setActiveChild(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? GsColors.accent : GsColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? GsColors.accent : GsColors.border2),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        active ? Colors.white : GsColors.accentLight,
                    child: Text(
                      (c['avatar'] as String? ?? name.characters.first)
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 12,
                          color: GsColors.accent,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name.split(' ').first,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : GsColors.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Date selector ───────────────────────────────────────────────────

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final isToday = appState.logDate == todayISO();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(
            color: isToday ? GsColors.border : GsColors.estimated),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: GsColors.text2),
            onPressed: () => appState.shiftLogDate(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                isToday
                    ? '${i18n.t('nav.today', 'Today')} · ${appState.logDate}'
                    : appState.logDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isToday ? GsColors.text : GsColors.estimated,
                ),
              ),
            ),
          ),
          if (!isToday)
            TextButton(
              onPressed: () => appState.setLogDate(todayISO()),
              child: Text(i18n.t('nav.today', 'Today'),
                  style: const TextStyle(
                      fontSize: 12, color: GsColors.accent)),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: GsColors.text2),
            onPressed: isToday ? null : () => appState.shiftLogDate(1),
          ),
        ],
      ),
    );
  }
}

// ── Cards ───────────────────────────────────────────────────────────

class _NutritionCard extends StatelessWidget {
  const _NutritionCard({required this.nutrition, required this.i18n});
  final Map<String, dynamic>? nutrition;
  final I18n i18n;

  double _g(String key) => (nutrition?[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final breakfast = _g('protein_breakfast_g');
    final lunch = _g('protein_lunch_g');
    final dinner = _g('protein_dinner_g');
    final total = breakfast + lunch + dinner;
    final calcium = _g('calcium_mg');
    final fluids = _g('fluids_ml');
    final protein = t('common.protein', 'Protein');

    return _GsCard(
      title: t('common.nutrition', 'Nutrition'),
      accentColor: GsColors.accent,
      child: nutrition == null
          ? _EmptyNote(t('today.nutrition.empty'))
          : Column(
              children: [
                _MetricRow('$protein — ${t('meal.breakfast', 'Breakfast')}',
                    '${_fmt(breakfast)} g'),
                _MetricRow('$protein — ${t('meal.lunch', 'Lunch')}',
                    '${_fmt(lunch)} g'),
                _MetricRow('$protein — ${t('meal.dinner', 'Dinner')}',
                    '${_fmt(dinner)} g'),
                _MetricRow(t('today.nutrition.protein_total'),
                    '${_fmt(total)} g',
                    bold: true),
                const Divider(height: 20, color: GsColors.border),
                _MetricRow(t('common.calcium', 'Calcium'),
                    '${_fmt(calcium)} mg'),
                _MetricRow(t('today.nutrition.hydration', 'Fluids'),
                    '${_fmt(fluids)} ml'),
              ],
            ),
    );
  }
}

/// Per-item food log for the selected date — the reviewable list the
/// PWA shows under "Logged today", with the same per-item delete undo.
class _LoggedFoodCard extends StatelessWidget {
  const _LoggedFoodCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final items = appState.nutritionLogItems;
    final totalProtein = items.fold<double>(
        0, (sum, i) => sum + ((i['protein_g'] as num?)?.toDouble() ?? 0));
    return _GsCard(
      title: t('flutter.food_log', 'Food log'),
      accentColor: GsColors.accent,
      trailing: items.isEmpty
          ? null
          : Text(
              '${items.length} ${t('flutter.items', 'items')} · ${_fmt(totalProtein)} ${t('flutter.g_protein', 'g protein')}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accent)),
      child: items.isEmpty
          ? _EmptyNote(t('today.nutrition.empty'))
          : Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['food_name'] as String? ?? 'Food',
                            style: const TextStyle(fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${item['meal_slot'] ?? ''} · ${_fmt((item['protein_g'] as num?)?.toDouble() ?? 0)} g',
                          style: const TextStyle(
                              fontSize: 12, color: GsColors.text2),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close,
                              size: 16, color: GsColors.text3),
                          onPressed: () async {
                            final err = await appState
                                .deleteNutritionLogItem(item['item_id']);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: GsColors.flag,
                                      content: Text(
                                          '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard(
      {required this.items, required this.appState, required this.i18n});
  final List<Map<String, dynamic>> items;
  final AppState appState;
  final I18n i18n;

  static const _tierColor = {
    'high_impact': GsColors.flag,
    'weight_bearing': GsColors.accent,
    'cardio': GsColors.measured,
    'flexibility': GsColors.estimated,
    'lifestyle': GsColors.estimated,
  };

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final totalMin = items.fold<double>(
        0, (sum, i) => sum + ((i['duration_min'] as num?)?.toDouble() ?? 0));

    return _GsCard(
      title: t('common.activity', 'Activity'),
      accentColor: GsColors.measured,
      trailing: items.isEmpty
          ? null
          : Text('${_fmt(totalMin)} ${t('flutter.min', 'min')}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.measured)),
      child: items.isEmpty
          ? _EmptyNote(t('flutter.no_activity_logged'))
          : Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _tierColor[item['tier']] ?? GsColors.text3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['display_name'] as String? ?? 'Activity',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        Text(
                          item['unit'] == 'reps'
                              ? '${item['duration_value'] ?? '?'} ${t('flutter.reps', 'reps')}'
                              : '${_fmt((item['duration_min'] as num?)?.toDouble() ?? 0)} ${t('flutter.min', 'min')}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: GsColors.text2,
                              fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close,
                              size: 16, color: GsColors.text3),
                          onPressed: () async {
                            final err = await appState
                                .deleteActivityItem(item['item_id']);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: GsColors.flag,
                                      content: Text(
                                          '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _GsCard extends StatelessWidget {
  const _GsCard({
    required this.title,
    required this.accentColor,
    required this.child,
    this.trailing,
  });
  final String title;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(GsRadius.md)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentColor)),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: GsColors.text2)),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: bold ? GsColors.accent : GsColors.text)),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: GsColors.text3)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GsColors.flagLight,
        borderRadius: BorderRadius.circular(GsRadius.sm),
        border: Border.all(color: GsColors.flag),
      ),
      child: Text(message,
          style: const TextStyle(fontSize: 12.5, color: GsColors.flagDark)),
    );
  }
}
