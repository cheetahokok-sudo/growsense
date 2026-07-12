import 'package:flutter/material.dart';

import '../activity_data.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// Activity tab — 30-activity browser with tier filter tabs,
/// mirroring the PWA's activity browser. Tapping Log opens a
/// bottom sheet (modal-sheet equivalent) with duration presets and
/// an outdoor toggle, then inserts a daily_activity_items row.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String? _tier; // null = all
  String _query = '';

  static const tierColors = {
    'high_impact': GsColors.flag,
    'weight_bearing': GsColors.accent,
    'cardio': GsColors.measured,
    'flexibility': GsColors.estimated,
    'lifestyle': GsColors.estimated,
  };

  List<Activity> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final a in activityLibrary)
        if ((_tier == null ||
                a.tier == _tier ||
                // FLEX filter folds lifestyle in, same as the PWA's
                // badge config mapping lifestyle → flex styling.
                (_tier == 'flexibility' && a.tier == 'lifestyle')) &&
            (q.isEmpty ||
                a.displayName.toLowerCase().contains(q) ||
                a.category.toLowerCase().contains(q) ||
                (a.note ?? '').toLowerCase().contains(q)))
          a,
    ];
  }

  Future<void> _openLogSheet(Activity act) async {
    final result = await showModalBottomSheet<({int value, bool outdoor})>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GsRadius.lg)),
      ),
      builder: (context) => _ActivityLogSheet(activity: act, i18n: widget.i18n),
    );
    if (result == null || !mounted) return;

    final err = await widget.appState.recordActivityItem(
      activityId: act.id,
      displayName: act.displayName,
      category: act.category,
      tier: act.tier,
      rawValue: result.value,
      unit: act.unit,
      isOutdoor: result.outdoor,
    );
    if (!mounted) return;
    final t = widget.i18n.t;
    final unitLabel = act.unit == 'reps'
        ? t('flutter.reps', 'reps')
        : t('flutter.min', 'min');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(
          err == null
              ? '${act.emoji} ${act.displayName} · ${result.value} $unitLabel${result.outdoor ? ' ☀️' : ''}'
              : '${t('flutter.could_not_save_activity', 'Could not save activity')}: $err',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: t(
                'flutter.search_activities',
                'Search {n} activities…',
                {'n': '${activityLibrary.length}'},
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: GsColors.text3,
              ),
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
              _TierChip(
                label: t('flutter.all', 'All'),
                color: GsColors.text2,
                selected: _tier == null,
                onTap: () => setState(() => _tier = null),
              ),
              for (final tier in [
                'high_impact',
                'weight_bearing',
                'cardio',
                'flexibility',
              ])
                _TierChip(
                  label: t(
                    'flutter.tier_short.$tier',
                    activityTierConfig[tier]!.shortLabel,
                  ),
                  color: tierColors[tier]!,
                  selected: _tier == tier,
                  onTap: () => setState(() => _tier = tier),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    t('flutter.no_activity_match', 'No activities match.'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: GsColors.text3,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final act = _filtered[i];
                    final tierLabel = t(
                      'flutter.tier.${act.tier}',
                      activityTierConfig[act.tier]!.label,
                    );
                    final color = tierColors[act.tier]!;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: GsColors.surface,
                        borderRadius: BorderRadius.circular(GsRadius.md),
                        border: Border.all(color: GsColors.border),
                      ),
                      child: Row(
                        children: [
                          Text(act.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  act.displayName,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tierLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 32,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(52, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: () => _openLogSheet(act),
                              child: Text(
                                t('flutter.log_btn', 'Log'),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
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
            color: selected ? color : GsColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : GsColors.border2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : GsColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Duration picker sheet — same presets/defaults as the PWA
/// (standard_min 30, small_min 2, reps 40) plus the outdoor toggle.
class _ActivityLogSheet extends StatefulWidget {
  const _ActivityLogSheet({required this.activity, required this.i18n});
  final Activity activity;
  final I18n i18n;

  @override
  State<_ActivityLogSheet> createState() => _ActivityLogSheetState();
}

class _ActivityLogSheetState extends State<_ActivityLogSheet> {
  late int _value;
  late bool _outdoor;

  List<int> get _presets => switch (widget.activity.presets) {
    'reps' => durationPresetsReps,
    'small_min' => durationPresetsSmallMin,
    _ => durationPresetsMin,
  };

  @override
  void initState() {
    super.initState();
    _value = switch (widget.activity.presets) {
      'reps' => 40,
      'small_min' => 2,
      _ => 30,
    };
    _outdoor = widget.activity.outdoor;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final act = widget.activity;
    final tierLabel = t(
      'flutter.tier.${act.tier}',
      activityTierConfig[act.tier]!.label,
    );
    final color = _ActivityScreenState.tierColors[act.tier]!;
    final unitLabel = act.unit == 'reps'
        ? t('flutter.reps', 'reps')
        : t('flutter.min', 'min');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(act.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        act.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tierLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (act.note != null) ...[
              const SizedBox(height: 10),
              Text(
                act.note!,
                style: const TextStyle(fontSize: 11.5, color: GsColors.text2),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _presets)
                  GestureDetector(
                    onTap: () => setState(() => _value = p),
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _value == p
                            ? GsColors.accentLight
                            : GsColors.surface2,
                        borderRadius: BorderRadius.circular(GsRadius.sm),
                        border: Border.all(
                          color: _value == p
                              ? GsColors.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$p',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _value == p
                                  ? GsColors.accentDark
                                  : GsColors.text,
                            ),
                          ),
                          Text(
                            unitLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: GsColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeThumbColor: GsColors.accent,
              title: Text(
                t('flutter.outdoor', 'Outdoor ☀️'),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                t('flutter.outdoor_sub', 'Sunlight → vitamin D synthesis'),
                style: const TextStyle(fontSize: 11, color: GsColors.text3),
              ),
              value: _outdoor,
              onChanged: (v) => setState(() => _outdoor = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, (value: _value, outdoor: _outdoor)),
              child: Text('${t('flutter.log_btn', 'Log')} $_value $unitLabel'),
            ),
          ],
        ),
      ),
    );
  }
}
