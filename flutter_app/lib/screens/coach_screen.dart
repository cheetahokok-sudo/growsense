import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'today_hud.dart';

/// AI Coach tab — v1 is deliberately rule-based: prioritized insight
/// cards computed from the same readiness components the HUD uses,
/// labeled honestly as such. The conversational coach (the PWA's
/// ai.* strings) plugs in here later.
class CoachScreen extends StatelessWidget {
  const CoachScreen(
      {super.key,
      required this.appState,
      required this.i18n,
      required this.onQuickLog});
  final AppState appState;
  final I18n i18n;
  final void Function(String action) onQuickLog;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.activeChildRow == null) {
          return Center(
              child: Text(t('flutter.no_child_selected', 'No child selected'),
                  style: const TextStyle(color: GsColors.text3)));
        }
        final s = computeHudScores(appState);

        // Rank the three systems; lead with the weakest one — that's
        // the "biggest lever" card, then component-level gaps.
        final systems = [
          ('sleep', s.slpPct),
          ('activity', s.actPct),
          ('nutrition', s.nutPct),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        final weakest = systems.first;

        final cards = <Widget>[];
        if (s.nutPct >= 0.85 && s.actPct >= 0.85 && s.slpPct >= 0.85) {
          cards.add(_InsightCard(
            emoji: '🎉',
            color: GsColors.accent,
            title: t('today.hud.title', 'Readiness reading'),
            body: t('flutter.coach.all_good'),
          ));
        } else {
          if (weakest.$1 == 'sleep') {
            cards.add(_InsightCard(
              emoji: '😴',
              color: GsColors.estimated,
              title: t('flutter.coach.biggest_lever', 'Biggest lever today'),
              body: t('flutter.coach.sleep_low'),
              actionLabel: t('flutter.log_sleep', 'Log sleep'),
              onAction: () => onQuickLog('sleep'),
            ));
          } else if (weakest.$1 == 'activity') {
            cards.add(_InsightCard(
              emoji: '🏀',
              color: GsColors.measured,
              title: t('flutter.coach.biggest_lever', 'Biggest lever today'),
              body: t('flutter.coach.activity_low'),
              actionLabel: t('flutter.log_activity', 'Log activity'),
              onAction: () => onQuickLog('activity'),
            ));
          }
          // Component gaps, shown regardless of which system leads
          if (s.pR < 0.9) {
            final gapG =
                ((1 - s.pR) * s.proteinBoostTarget).ceil();
            cards.add(_InsightCard(
              emoji: '🍗',
              color: GsColors.accent,
              title: t('common.protein', 'Protein'),
              body: t('flutter.coach.protein_gap', null, {'n': '$gapG'}),
              actionLabel: t('flutter.log_food', 'Log food'),
              onAction: () => onQuickLog('food'),
            ));
          }
          if (s.cR < 0.9) {
            cards.add(_InsightCard(
              emoji: '🥛',
              color: GsColors.accent,
              title: t('common.calcium', 'Calcium'),
              body: t('flutter.coach.calcium_gap', null,
                  {'n': '${(s.cR * 100).round()}'}),
              actionLabel: t('flutter.log_food', 'Log food'),
              onAction: () => onQuickLog('food'),
            ));
          }
          if (weakest.$1 == 'nutrition' && s.slpPct < 0.85) {
            cards.add(_InsightCard(
              emoji: '😴',
              color: GsColors.estimated,
              title: t('common.sleep', 'Sleep'),
              body: t('flutter.coach.sleep_low'),
              actionLabel: t('flutter.log_sleep', 'Log sleep'),
              onAction: () => onQuickLog('sleep'),
            ));
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(t('ai.subtitle',
                'Context from this child\'s logged data — not a substitute for your pediatrician'),
                style:
                    const TextStyle(fontSize: 11.5, color: GsColors.text2)),
            const SizedBox(height: 12),
            ...[
              for (final card in cards) ...[card, const SizedBox(height: 12)]
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GsColors.surface2,
                borderRadius: BorderRadius.circular(GsRadius.sm),
              ),
              child: Text(t('flutter.coach.beta'),
                  style:
                      const TextStyle(fontSize: 10.5, color: GsColors.text3)),
            ),
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.emoji,
    required this.color,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
  final String emoji;
  final Color color;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

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
              color: color,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(GsRadius.md)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body,
                    style: const TextStyle(
                        fontSize: 13, height: 1.45, color: GsColors.text)),
                if (actionLabel != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: onAction,
                        child: Text(actionLabel!,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
