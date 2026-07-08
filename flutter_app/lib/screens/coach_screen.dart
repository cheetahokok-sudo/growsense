import 'package:flutter/material.dart';

import '../app_state.dart';
import '../coach_library.dart';
import '../growth_math.dart';
import '../i18n.dart';
import '../theme.dart';

/// AI Coach — a chat that answers from GrowSense's own question library
/// (Supabase ai_coach_questions + the bundled pilot batch), filling
/// each answer template with this child's real data. No external LLM:
/// free text is matched to the closest library question by word
/// overlap, and only answers with a verified source show a citation.
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
  final String? citation;
  final List<CoachQuestion> followUps;
  _Msg(this.text, this.fromUser, {this.citation, this.followUps = const []});
}

class _CoachScreenState extends State<CoachScreen> {
  CoachLibrary? _lib;
  WhoReference? _who;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  String _category = 'all';

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

  void _ask(String text, {String? exactHint}) {
    final lib = _lib;
    if (lib == null || text.trim().isEmpty) return;
    setState(() => _messages.add(_Msg(text.trim(), true)));
    final answerable = _answerable;
    final matched = findBestMatch(text, answerable, exactHint: exactHint);
    final t = widget.i18n.t;

    if (matched?.answerTemplate != null) {
      final filled = fillTemplate(matched!.answerTemplate!, _ctx);
      // Up to 3 same-category follow-ups that are answerable now.
      final follows = [
        for (final q in answerable)
          if (q.category == matched.category && q.text != matched.text) q,
      ]..sort((a, b) => a.priority.compareTo(b.priority));
      setState(() => _messages.add(_Msg(filled, false,
          citation: matched.citation, followUps: follows.take(3).toList())));
    } else {
      setState(() => _messages.add(_Msg(
          t('flutter.coach.no_match',
              "I couldn't match that to one of my prepared answers. Try rephrasing, tap a suggested question, or ask your pediatrician. (This coach answers from a verified library — no live AI model is used.)"),
          false)));
    }
    _input.clear();
    _scrollDown();
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
                  ? _WelcomeAndSuggestions(
                      i18n: widget.i18n,
                      answerable: _answerable,
                      category: _category,
                      onCategory: (c) => setState(() => _category = c),
                      onAsk: (q) => _ask(q.text, exactHint: q.text),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _Bubble(
                        msg: _messages[i],
                        onFollowUp: (q) => _ask(q.text, exactHint: q.text),
                      ),
                    ),
            ),
            _Composer(
              controller: _input,
              hint: t('ai.welcome_message', 'Ask about your child’s growth…'),
              onSend: () => _ask(_input.text),
            ),
          ],
        );
      },
    );
  }
}

class _WelcomeAndSuggestions extends StatelessWidget {
  const _WelcomeAndSuggestions({
    required this.i18n,
    required this.answerable,
    required this.category,
    required this.onCategory,
    required this.onAsk,
  });
  final I18n i18n;
  final List<CoachQuestion> answerable;
  final String category;
  final void Function(String) onCategory;
  final void Function(CoachQuestion) onAsk;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final cats = <String>{for (final q in answerable) q.category};
    final shown = [
      for (final q in answerable)
        if (category == 'all' || q.category == category) q,
    ]..sort((a, b) => a.priority.compareTo(b.priority));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.circular(GsRadius.md),
            border: Border.all(color: GsColors.border),
            boxShadow: gsShadow,
          ),
          child: Text(
            t('ai.subtitle',
                'I answer from GrowSense’s verified library using this child’s logged data. I’m not a doctor — bring the Analytics trend to your pediatrician for decisions.'),
            style: const TextStyle(fontSize: 12.5, color: GsColors.text2),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _Chip(
                  label: t('flutter.all', 'All'),
                  selected: category == 'all',
                  onTap: () => onCategory('all')),
              for (final c in cats)
                _Chip(
                    label: coachCategoryLabels[c] ?? c,
                    selected: category == c,
                    onTap: () => onCategory(c)),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
                child: Text(q.text,
                    style: const TextStyle(
                        fontSize: 13, color: GsColors.text)),
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
          decoration: BoxDecoration(
            color: GsColors.accent,
            borderRadius: const BorderRadius.only(
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
      {required this.controller, required this.hint, required this.onSend});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

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
              onTap: onSend,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: GsColors.accent, shape: BoxShape.circle),
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

class _Chip extends StatelessWidget {
  const _Chip(
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
      ),
    );
  }
}
