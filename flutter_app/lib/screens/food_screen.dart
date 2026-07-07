import 'package:flutter/material.dart';

import '../app_state.dart';
import '../food_data.dart';
import '../i18n.dart';
import '../theme.dart';

/// Food tab — the 90-preset library with search + category filter,
/// mirroring the PWA's food browse modal. Tapping Log records a
/// nutrition_log_items row for the active child + logDate under the
/// selected meal slot.
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  List<FoodItem> _all = [];
  String _query = '';
  String? _category; // null = all

  @override
  void initState() {
    super.initState();
    loadFoodReference().then((foods) {
      if (mounted) setState(() => _all = foods);
    });
  }

  List<FoodItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final f in _all)
        if ((_category == null || f.category == _category) &&
            (q.isEmpty ||
                f.name.toLowerCase().contains(q) ||
                (f.prepNote ?? '').toLowerCase().contains(q)))
          f,
    ];
  }

  Future<void> _log(FoodItem food) async {
    final err = await widget.appState.recordNutritionLogItem(
      foodId: food.id,
      foodName: food.name,
      proteinG: _round1(food.proteinPerServing),
      zincMg: food.zincPerServing == null ? null : _round2(food.zincPerServing!),
      calciumMg:
          food.calciumPerServing == null ? null : _round1(food.calciumPerServing!),
    );
    if (!mounted) return;
    final t = widget.i18n.t;
    final slot = t('meal.${widget.appState.activeMealSlot}',
        widget.appState.activeMealSlot);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
      content: Text(err == null
          ? '${food.emoji} ${food.name} · ${_fmtG(food.proteinPerServing)} ${t('flutter.g_protein', 'g protein')} → $slot'
          : '${t('flutter.not_saved', 'Not saved')}: $err'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: t('flutter.search_foods', 'Search {n} foods…',
                      {'n': '${_all.length}'}),
                  prefixIcon:
                      const Icon(Icons.search, size: 20, color: GsColors.text3),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _CategoryChip(
                    label: t('flutter.all', 'All'),
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  for (final c in foodCategories)
                    _CategoryChip(
                      label: t('flutter.cat.$c', c),
                      selected: _category == c,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _MealSlotBar(appState: appState, i18n: widget.i18n),
            Expanded(
              child: _all.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _FoodRow(
                          food: _filtered[i],
                          onLog: _log,
                          i18n: widget.i18n),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GsColors.accent : GsColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? GsColors.accent : GsColors.border2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : GsColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Logging for" segmented control — same four slots as the PWA.
class _MealSlotBar extends StatelessWidget {
  const _MealSlotBar({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  static const _slots = ['breakfast', 'lunch', 'dinner', 'snack'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(GsRadius.sm + 3),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _slots.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => appState.setMealSlot(_slots[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: appState.activeMealSlot == _slots[i]
                          ? GsColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(GsRadius.sm),
                      boxShadow: appState.activeMealSlot == _slots[i]
                          ? gsShadow
                          : null,
                    ),
                    child: Text(
                      i18n.t('meal.${_slots[i]}', _slots[i]),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: appState.activeMealSlot == _slots[i]
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: appState.activeMealSlot == _slots[i]
                            ? GsColors.text
                            : GsColors.text2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow(
      {required this.food, required this.onLog, required this.i18n});
  final FoodItem food;
  final void Function(FoodItem) onLog;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
      ),
      child: Row(
        children: [
          Text(food.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(food.name,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (food.prepNote != null) food.prepNote!,
                    '${_fmtG(food.servingGrams)} g · ${i18n.t('flutter.serving', 'serving')}',
                  ].join(' · '),
                  style:
                      const TextStyle(fontSize: 11.5, color: GsColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_fmtG(food.proteinPerServing)} g',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accent)),
              Text(i18n.t('flutter.protein', 'protein'),
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.text3)),
            ],
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(52, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => onLog(food),
              child: Text(i18n.t('flutter.log_btn', 'Log'),
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

double _round1(double v) => (v * 10).roundToDouble() / 10;
double _round2(double v) => (v * 100).roundToDouble() / 100;

String _fmtG(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
