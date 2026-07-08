import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../coach_library.dart';
import '../growth_math.dart';
import '../i18n.dart';
import '../theme.dart';
import 'today_hud.dart';

/// AI Coach — a chat that answers from GrowSense's own question library
/// (Supabase ai_coach_questions + the bundled pilot batch), filling
/// each answer template with this child's real data. No external LLM.
///
/// Warmth without over-familiarity: the greeting and daily summary
/// address the child by name to feel caring, but individual answers
/// only use the name when they actually reference personal data (the
/// template carries a {{name}} token) — generic educational answers
/// stay name-free by design.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _Msg {
  final String text;
  final bool fromUser;
  final bool thinking;
  final String? citation;
  final List<CoachQuestion> followUps;
  _Msg(this.text, this.fromUser,
      {this.thinking = false, this.citation, this.followUps = const []});
}

class _CoachScreenState extends State<CoachScreen> {
  CoachLibrary? _lib;
  WhoReference? _who;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  String _category = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CoachLibrary.load(widget.appState.sb).then((lib) {
      if (mounted) setState(() => _lib = lib);
    });
    loadWhoReference().then((w) {
      if (mounted) setState(() => _who = w);
    });
    widget.appState.loadClinicalIfNeeded();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _ctx => buildCoachContext(widget.appState, _who);

  List<CoachQuestion> get _answerable {
    final lib = _lib;
    if (lib == null) return [];
    final ctx = _ctx;
    final tags = availableDataTags(ctx);
    final age = ctx['ageYearsNum'] as double?;
    return [
      for (final q in lib.questions)
        if (questionAnswerable(q, tags, age) && q.answerTemplate != null) q,
    ];
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _ask(String text, {String? exactHint}) async {
    final lib = _lib;
    if (lib == null || text.trim().isEmpty || _busy) return;
    final t = widget.i18n.t;

    setState(() {
      _busy = true;
      _messages.add(_Msg(text.trim(), true));
      _messages.add(_Msg('', false, thinking: true)); // "searching…"
    });
    _input.clear();
    _scrollDown();

    // A brief, honest pause so the parent sees the library being
    // searched — the matching itself is instant, this is deliberate
    // feedback, not a fake delay dressed up as more than it is.
    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;

    final answerable = _answerable;
    final matched = findBestMatch(text, answerable, exactHint: exactHint);

    setState(() {
      _messages.removeWhere((m) => m.thinking);
      if (matched?.answerTemplate != null) {
        final filled = fillTemplate(matched!.answerTemplate!, _ctx);
        final follows = [
          for (final q in answerable)
            if (q.category == matched.category && q.text != matched.text) q,
        ]..sort((a, b) => a.priority.compareTo(b.priority));
        _messages.add(_Msg(filled, false,
            citation: matched.citation, followUps: follows.take(3).toList()));
      } else {
        _messages.add(_Msg(t('flutter.coach.no_match'), false));
      }
      _busy = false;
    });
    _scrollDown();
  }

  void _resetChat() {
    setState(() {
      _messages.clear();
      _category = 'all';
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        if (widget.appState.activeChildRow == null) {
          return Center(
              child: Text(t('flutter.no_child_selected', 'No child selected'),
                  style: const TextStyle(color: GsColors.text3)));
        }
        if (_lib == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _WelcomeView(
                      appState: widget.appState,
                      i18n: widget.i18n,
                      who: _who,
                      answerable: _answerable,
                      category: _category,
                      onCategory: (c) => setState(() => _category = c),
                      onAsk: (q) => _ask(q.text, exactHint: q.text),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _messages.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GestureDetector(
                                onTap: _resetChat,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: GsColors.accentLight,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: GsColors.accent
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add_comment_outlined,
                                          size: 14, color: GsColors.accentDark),
                                      const SizedBox(width: 5),
                                      Text(
                                          t('flutter.coach.new_chat',
                                              'New chat'),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: GsColors.accentDark)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final msg = _messages[i - 1];
                        if (msg.thinking) {
                          return _ThinkingBubble(
                              i18n: widget.i18n,
                              name: (widget.appState.activeChildRow?['name']
                                      as String? ??
                                  '')
                                  .split(' ')
                                  .first);
                        }
                        return _Bubble(
                          msg: msg,
                          onFollowUp: (q) => _ask(q.text, exactHint: q.text),
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _input,
              hint: t('flutter.coach.not_sure', 'Ask about growth…'),
              enabled: !_busy,
              onSend: () => _ask(_input.text),
            ),
          ],
        );
      },
    );
  }
}

// ── Welcome: greeting + daily summary + topic browser + suggestions ──

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({
    required this.appState,
    required this.i18n,
    required this.who,
    required this.answerable,
    required this.category,
    required this.onCategory,
    required this.onAsk,
  });
  final AppState appState;
  final I18n i18n;
  final WhoReference? who;
  final List<CoachQuestion> answerable;
  final String category;
  final void Function(String) onCategory;
  final void Function(CoachQuestion) onAsk;

  String _areaLabel(String area) => switch (area) {
        'nutrition' => i18n.t('common.nutrition', 'Nutrition'),
        'activity' => i18n.t('common.activity', 'Activity'),
        _ => i18n.t('common.sleep', 'Sleep'),
      };

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final name =
        (appState.activeChildRow?['name'] as String? ?? '').split(' ').first;
    final hour = DateTime.now().hour;
    final hi = hour < 12
        ? t('flutter.coach.hi_morning', 'Good morning')
        : hour < 18
            ? t('flutter.coach.hi_afternoon', 'Good afternoon')
            : t('flutter.coach.hi_evening', 'Good evening');

    // Daily summary from the same readiness math the Today tab uses.
    final s = computeHudScores(appState);
    final loggedToday = appState.nutritionLogItems.isNotEmpty ||
        appState.sleep != null ||
        appState.activityItems.isNotEmpty;
    final systems = [
      ('sleep', s.slpPct),
      ('activity', s.actPct),
      ('nutrition', s.nutPct),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final weakest = systems.first;
    final strongest = systems.last;

    // Weekly consistency nudge.
    final loggedDays = appState.weekLogDates.length;

    final cats = <String>{for (final q in answerable) q.category};
    final shown = [
      for (final q in answerable)
        if (category == 'all' || q.category == category) q,
    ]..sort((a, b) => a.priority.compareTo(b.priority));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        // Greeting + summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [GsColors.accent, GsColors.accentDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(GsRadius.md),
            boxShadow: gsShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$hi 👋',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 2),
              Text(
                  t('flutter.coach.how_is_today', 'How is {name} doing today?')
                      .replaceAll('{name}', name),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 10),
              if (!loggedToday)
                Text(
                    t('flutter.coach.no_logs_today')
                        .replaceAll('{name}', name),
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.92)))
              else ...[
                Text(
                    t('flutter.coach.summary_score')
                        .replaceAll('{name}', name)
                        .replaceAll('{score}', '${s.score}'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                    strongest.$2 >= 0.85
                        ? t('flutter.coach.summary_strong')
                            .replaceAll('{area}', _areaLabel(strongest.$1))
                        : t('flutter.coach.summary_focus')
                            .replaceAll('{area}', _areaLabel(weakest.$1)),
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.92))),
              ],
            ],
          ),
        ),
        if (loggedDays < 4) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GsColors.estimatedLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
              border:
                  Border.all(color: GsColors.estimated.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Text('📅', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      t('flutter.coach.weekly_reminder')
                          .replaceAll('{days}', '$loggedDays'),
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: GsColors.estimatedDark)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(t('flutter.coach.browse_topics', 'Browse topics'),
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(t('flutter.coach.not_sure',
            'Not sure what to ask? Pick a topic or a question below.'),
            style: const TextStyle(fontSize: 11.5, color: GsColors.text3)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TopicChip(
                label: t('flutter.all', 'All'),
                selected: category == 'all',
                onTap: () => onCategory('all')),
            for (final c in cats)
              _TopicChip(
                  label: coachCategoryLabels[c] ?? c,
                  selected: category == c,
                  onTap: () => onCategory(c)),
          ],
        ),
        const SizedBox(height: 14),
        for (final q in shown.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onAsk(q),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: GsColors.surface,
                  borderRadius: BorderRadius.circular(GsRadius.md),
                  border: Border.all(color: GsColors.border2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(q.text,
                          style: const TextStyle(
                              fontSize: 13, color: GsColors.text)),
                    ),
                    const Icon(Icons.north_east,
                        size: 14, color: GsColors.text3),
                  ],
                ),
              ),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
                t('flutter.coach.no_questions',
                    'No suggested questions for this category yet — ask directly below.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: GsColors.text3)),
          ),
      ],
    );
  }
}

// ── Thinking bubble — animated dots + a rotating status line ─────────

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble({required this.i18n, required this.name});
  final I18n i18n;
  final String name;

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  int _stage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Swap the status line once partway through the ~850ms pause.
    _timer = Timer(const Duration(milliseconds: 430), () {
      if (mounted) setState(() => _stage = 1);
    });
  }

  @override
  void dispose() {
    _dots.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final label = _stage == 0
        ? t('flutter.coach.thinking_search', 'Searching the library…')
        : t('flutter.coach.thinking_data', "Checking {name}'s data…")
            .replaceAll('{name}', widget.name);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(GsRadius.md),
            topRight: Radius.circular(GsRadius.md),
            bottomRight: Radius.circular(GsRadius.md),
          ),
          border: Border.all(color: GsColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _dots,
              builder: (context, _) {
                return Row(
                  children: List.generate(3, (i) {
                    final phase = (_dots.value + i * 0.33) % 1.0;
                    final on = phase < 0.5;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: GsColors.accent
                              .withValues(alpha: on ? 0.9 : 0.25),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: GsColors.text3)),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onFollowUp});
  final _Msg msg;
  final void Function(CoachQuestion) onFollowUp;

  @override
  Widget build(BuildContext context) {
    if (msg.fromUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: GsColors.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(GsRadius.md),
              topRight: Radius.circular(GsRadius.md),
              bottomLeft: Radius.circular(GsRadius.md),
            ),
          ),
          child: Text(msg.text,
              style: const TextStyle(fontSize: 13.5, color: Colors.white)),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: GsColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(GsRadius.md),
                  topRight: Radius.circular(GsRadius.md),
                  bottomRight: Radius.circular(GsRadius.md),
                ),
                border: Border.all(color: GsColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.text,
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.5, color: GsColors.text)),
                  if (msg.citation != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.only(top: 7),
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: GsColors.border)),
                      ),
                      child: Text('Source: ${msg.citation}',
                          style: const TextStyle(
                              fontSize: 10, color: GsColors.text3)),
                    ),
                  ],
                ],
              ),
            ),
            if (msg.followUps.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final q in msg.followUps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: GestureDetector(
                    onTap: () => onFollowUp(q),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: GsColors.accentLight,
                        borderRadius: BorderRadius.circular(GsRadius.sm),
                      ),
                      child: Text('→ ${q.text}',
                          style: const TextStyle(
                              fontSize: 12, color: GsColors.accentDark)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer(
      {required this.controller,
      required this.hint,
      required this.onSend,
      required this.enabled});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: GsColors.surface,
        border: Border(top: BorderSide(color: GsColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: enabled ? onSend : null,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: enabled ? GsColors.accent : GsColors.text3,
                    shape: BoxShape.circle),
                child: const Icon(Icons.arrow_upward,
                    size: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GsColors.accent : GsColors.surface,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: selected ? GsColors.accent : GsColors.border2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : GsColors.text2)),
      ),
    );
  }
}
