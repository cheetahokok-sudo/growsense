import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../coach_digest.dart';
import '../coach_library.dart';
import '../food_data.dart';
import '../growth_math.dart';
import '../i18n.dart';
import '../theme.dart';
import 'today_hud.dart';

/// AI Coach — a chat that answers from GrowSense's own question library
/// (Supabase ai_coach_questions + the bundled pilot batch), filling each
/// answer template with this child's real data.
///
/// Library first, model second. When the library has no match AND the
/// project-wide `system_settings.ai_coach_mode` is 'live_ai' AND the
/// account is premium, the question goes to the ai-coach-proxy Edge
/// Function (Haiku 4.5) and the answer is labelled "Live AI" with no
/// citation. Library answers are human-verified and carry real sources,
/// so re-answering them with a model would spend a credit to get a
/// worse answer — credits go only where the library falls short.
///
/// The monthly cap is enforced server-side; this screen shows the
/// remaining count and the refusal reasons, but is not the gate.
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

  /// Answered by the model rather than the verified library. Carries a
  /// chip and never a citation — a generated answer must not borrow a
  /// source it didn't earn.
  final bool live;
  _Msg(this.text, this.fromUser,
      {this.thinking = false,
      this.citation,
      this.followUps = const [],
      this.live = false});
}

class _CoachScreenState extends State<CoachScreen> {
  CoachLibrary? _lib;
  WhoReference? _who;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  String _category = 'all';
  bool _busy = false;

  /// Live-AI state: the project-wide mode and this month's allowance.
  bool _liveMode = false;
  int? _liveCap;
  int _liveUsed = 0;

  bool get _liveAvailable =>
      _liveMode && widget.appState.isPremium && _liveCap != 0;

  int? get _liveRemaining =>
      _liveCap == null ? null : math.max(0, _liveCap! - _liveUsed);

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
    _loadLiveState();
  }

  Future<void> _loadLiveState() async {
    final mode = await widget.appState.aiCoachMode();
    if (!mounted) return;
    setState(() => _liveMode = mode == 'live_ai');
    if (!_liveMode || !widget.appState.isPremium) return;
    final usage = await widget.appState.liveAiUsage();
    if (!mounted) return;
    setState(() {
      _liveCap = usage.cap;
      _liveUsed = usage.used;
    });
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

    if (matched?.answerTemplate != null) {
      setState(() {
        _messages.removeWhere((m) => m.thinking);
        final filled = fillTemplate(matched!.answerTemplate!, _ctx);
        final follows = [
          for (final q in answerable)
            if (q.category == matched.category && q.text != matched.text) q,
        ]..sort((a, b) => a.priority.compareTo(b.priority));
        _messages.add(_Msg(filled, false,
            citation: matched.citation, followUps: follows.take(3).toList()));
        _busy = false;
      });
      _scrollDown();
      return;
    }

    // Library-first, live only on a miss. Deliberately NOT the PWA's
    // route-everything-to-the-model behaviour: the library's answers are
    // human-verified and carry real citations, so re-answering them with
    // a model would spend a credit to get a worse answer. Credits go
    // exactly where the library falls short — which is the case that
    // sent a parent here in the first place.
    if (!_liveAvailable) {
      setState(() {
        _messages.removeWhere((m) => m.thinking);
        _messages.add(_Msg(t('flutter.coach.no_match'), false));
        _busy = false;
      });
      _scrollDown();
      return;
    }

    // Ground the answer in the food log when the question is about
    // food. The digest is an enhancement, never a gate — any failure
    // here still produces an (ungrounded but honest) live answer.
    String? digest;
    try {
      final foods = await loadFoodReference();
      final scan = scanCoachQuestion(text, foods);
      if (scan.nutritionRelated) {
        final rows = await widget.appState.loadCoachFoodRows(scan.windowDays);
        digest = buildFoodDigest(
          scan: scan,
          itemRows: rows.items,
          dailyRows: rows.daily,
          foodsById: {for (final f in foods) f.id: f},
          today: DateTime.now(),
          proteinTargetG: (_ctx['proteinTargetG'] as num?)?.toDouble(),
        );
      }
    } catch (e) {
      debugPrint('[coach] digest build failed, answering without: $e');
    }

    // Recent turns so follow-ups keep their subject ("and compared to
    // beef?"). The just-added question and the thinking bubble are
    // excluded; the proxy caps the list server-side anyway.
    final history = [
      for (final m in _messages)
        if (!m.thinking && m.text.isNotEmpty)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
    ];
    if (history.isNotEmpty) history.removeLast(); // the question itself
    final recent =
        history.length > 6 ? history.sublist(history.length - 6) : history;

    final res = await widget.appState.askCoachLive(
      system: coachSystemPrompt(_ctx, widget.i18n.code, foodDigest: digest),
      question: text.trim(),
      history: recent,
    );
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m.thinking);
      if (res.ok) {
        _liveUsed += 1; // the server already counted it
        _messages.add(_Msg(res.text!, false, live: true));
      } else {
        _messages.add(_Msg(
            switch (res.reason) {
              'cap_exceeded' => t(
                  'flutter.coach.live_capped',
                  'You\'ve used all your live AI answers this month. They reset on the 1st — the answer library below still works.'),
              'not_in_plan' => t('flutter.coach.live_not_in_plan',
                  'Live AI answers are part of Premium. The answer library is always free.'),
              'session_expired' => t('flutter.coach.live_session_expired',
                  'Your session expired — sign out and back in, then try again.'),
              _ => t('flutter.coach.live_failed',
                  'Couldn\'t reach the AI just now. The answer library below still works.'),
            },
            false));
        if (res.cap != null) _liveCap = res.cap;
        if (res.used != null) _liveUsed = res.used!;
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

  /// Pinned above the chat in both the welcome and conversation states:
  /// the live-AI credit chip (only when live answers are reachable — a
  /// parent who can't use them shouldn't be told what they're missing)
  /// and New chat (only when there's a conversation to reset). The old
  /// in-list New chat pill scrolled away with the messages; this doesn't.
  Widget _headerRow() {
    final t = widget.i18n.t;
    final showChip = _liveAvailable && _liveRemaining != null;
    final showReset = _messages.isNotEmpty;
    if (!showChip && !showReset) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          if (showChip)
            _CreditChip(
              remaining: _liveRemaining!,
              cap: _liveCap!,
              i18n: widget.i18n,
              onTap: _showCreditSheet,
            ),
          const Spacer(),
          if (showReset)
            GestureDetector(
              onTap: _resetChat,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: GsColors.accentLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: GsColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_comment_outlined,
                        size: 14, color: GsColors.accentDark),
                    const SizedBox(width: 5),
                    Text(t('flutter.coach.new_chat', 'New chat'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: GsColors.accentDark)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCreditSheet() {
    final t = widget.i18n.t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: GsColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Text(t('flutter.coach.credits_title', 'Live AI answers'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: GsColors.text)),
                const SizedBox(height: 10),
                Text(
                    t('flutter.coach.credits_library',
                        'Answers from the GrowSense library are free and human-verified — they never use one of your live answers.'),
                    style: const TextStyle(
                        fontSize: 12.5, color: GsColors.text2, height: 1.5)),
                const SizedBox(height: 8),
                Text(
                    t(
                        'flutter.coach.credits_live',
                        'When the library has no answer, a live AI answer uses 1 of your {cap} monthly answers.',
                        {'cap': '${_liveCap ?? 0}'}),
                    style: const TextStyle(
                        fontSize: 12.5, color: GsColors.text2, height: 1.5)),
                const SizedBox(height: 8),
                Text(
                    t('flutter.coach.credits_reset_body',
                        'Your count resets on the 1st of each month.'),
                    style: const TextStyle(
                        fontSize: 12.5, color: GsColors.text2, height: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
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
            _headerRow(),
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
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final msg = _messages[i];
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
                          i18n: widget.i18n,
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
  const _Bubble(
      {required this.msg, required this.onFollowUp, required this.i18n});
  final _Msg msg;
  final void Function(CoachQuestion) onFollowUp;
  final I18n i18n;

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
                  // A generated answer says so. Library answers carry a
                  // verified source; this one carries a label instead.
                  if (msg.live) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: GsColors.estimatedLight,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                          i18n.t('flutter.coach.live_chip', 'Live AI'),
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: GsColors.estimatedDark)),
                    ),
                    const SizedBox(height: 7),
                  ],
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

/// The monthly live-AI allowance as `remaining/cap` with a small
/// depletion bar. Colour follows the app's data-honesty semantics:
/// accent green while healthy, estimated gold when running low, flag
/// red only at zero — where "resets on the 1st" tells the parent it's
/// temporary, not broken. Tapping opens the explainer sheet.
class _CreditChip extends StatelessWidget {
  const _CreditChip(
      {required this.remaining,
      required this.cap,
      required this.i18n,
      required this.onTap});
  final int remaining;
  final int cap;
  final I18n i18n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = remaining <= 0;
    final low = !out && remaining <= 10;
    final bg = out
        ? GsColors.flagLight
        : low
            ? GsColors.estimatedLight
            : GsColors.accentLight;
    final fg = out
        ? GsColors.flagDark
        : low
            ? GsColors.estimatedDark
            : GsColors.accentDark;
    final main = out
        ? GsColors.flag
        : low
            ? GsColors.estimated
            : GsColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: main.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: fg),
            const SizedBox(width: 5),
            Text('$remaining/$cap',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            if (out) ...[
              const SizedBox(width: 5),
              Text(i18n.t('flutter.coach.credits_reset', 'resets on the 1st'),
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
            ] else ...[
              const SizedBox(width: 6),
              Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: main.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: cap <= 0 ? 0 : (remaining / cap).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: main,
                      borderRadius: BorderRadius.circular(2),
                    ),
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
                // A live answer costs 1 credit regardless of length, but
                // the question rides the model's input bill — so cap it
                // silently (no counter, typing just stops). 500 chars
                // fits any real question a parent asks.
                maxLength: 500,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  counterText: '',
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
