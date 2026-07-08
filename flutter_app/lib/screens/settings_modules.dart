// ══════════════════════════════════════════════════════════════════
// Account/settings sub-screens: Add child + Share with doctor.
// Both mirror the PWA's account-screen functions and write the same
// tables (children, doctor_patient_assignments) — see app.js
// addChild() / shareChildWithDoctor() for the backend contracts.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

// ── Add child ───────────────────────────────────────────────────────

class AddChildScreen extends StatefulWidget {
  const AddChildScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _name = TextEditingController();
  final _gestWeeks = TextEditingController();
  final _birthWeight = TextEditingController();
  final _birthLength = TextEditingController();
  String? _dob;
  String _sex = 'male';
  bool _isSga = false;
  bool _birthDetails = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _gestWeeks, _birthWeight, _birthLength]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final name = _name.text.trim();
    if (name.isEmpty || _dob == null) {
      _snack(t('flutter.child.need_fields', 'Name and date of birth required'));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState.addChild(
      name: name,
      dob: _dob!,
      sex: _sex,
      gestationalWeeks: int.tryParse(_gestWeeks.text),
      birthWeightKg: double.tryParse(_birthWeight.text),
      birthLengthCm: double.tryParse(_birthLength.text),
      isSga: _isSga,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      _snack('✅ $name ${t('flutter.child.added', 'added')}');
      Navigator.of(context).pop();
    } else {
      _snack('⚠️ $err');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final active = widget.appState.children
        .where((c) => c['status'] != 'archived')
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('flutter.child.add_title', 'Add a child'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GsColors.surface,
              borderRadius: BorderRadius.circular(GsRadius.md),
              border: Border.all(color: GsColors.border),
              boxShadow: gsShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    t('flutter.child.slots', '{n} of 4 profiles used',
                        {'n': '$active'}),
                    style: const TextStyle(
                        fontSize: 11, color: GsColors.text3)),
                const SizedBox(height: 12),
                TextField(
                    controller: _name,
                    decoration: _dec(t('flutter.child.name', 'Name'))),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _dob != null ? DateTime.parse(_dob!) : now,
                      firstDate: DateTime(now.year - 19),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setState(() => _dob = localISO(picked));
                    }
                  },
                  icon: const Icon(Icons.cake_outlined, size: 16),
                  label: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                        _dob ??
                            t('flutter.child.dob', 'Date of birth'),
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _sex,
                  decoration: _dec(t('flutter.child.sex', 'Biological sex')),
                  items: [
                    DropdownMenuItem(
                        value: 'male',
                        child: Text(t('common.male', 'Male'),
                            style: const TextStyle(fontSize: 13))),
                    DropdownMenuItem(
                        value: 'female',
                        child: Text(t('common.female', 'Female'),
                            style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _sex = v!),
                ),
                const SizedBox(height: 12),

                // Optional birth details — collapsed by default, most
                // parents won't need SGA/catch-up tracking.
                InkWell(
                  onTap: () =>
                      setState(() => _birthDetails = !_birthDetails),
                  child: Row(
                    children: [
                      Icon(
                          _birthDetails
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                          size: 16,
                          color: GsColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            t('flutter.child.birth_details',
                                'Birth details (for SGA / catch-up growth tracking)'),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: GsColors.accent)),
                      ),
                    ],
                  ),
                ),
                if (_birthDetails) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _gestWeeks,
                            keyboardType: TextInputType.number,
                            decoration: _dec(t('flutter.child.gest_weeks',
                                'Gestation (weeks)')))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _birthWeight,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: _dec(t(
                                'flutter.child.birth_weight',
                                'Birth weight (kg)')))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _birthLength,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _dec(t('flutter.child.birth_length',
                          'Birth length (cm)'))),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _isSga,
                    onChanged: (v) => setState(() => _isSga = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                        t('flutter.child.sga',
                            'Doctor confirmed SGA (small for gestational age)'),
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy
                      ? t('flutter.saving', 'Saving…')
                      : t('flutter.child.save', 'Add child')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Share with doctor / researcher ──────────────────────────────────

class ShareChildScreen extends StatefulWidget {
  const ShareChildScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<ShareChildScreen> createState() => _ShareChildScreenState();
}

class _ShareChildScreenState extends State<ShareChildScreen> {
  final _email = TextEditingController();
  dynamic _childId;
  List<Map<String, dynamic>> _shares = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final kids = widget.appState.children;
    if (kids.isNotEmpty) {
      _childId = kids.first['child_id'];
      _loadShares();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    final rows = await widget.appState.loadShares(_childId);
    if (mounted) setState(() => _shares = rows);
  }

  Future<void> _share() async {
    final t = widget.i18n.t;
    final email = _email.text.trim();
    if (_childId == null) {
      _snack(t('flutter.share.no_child', 'Add a child profile first'));
      return;
    }
    if (email.isEmpty) {
      _snack(t('flutter.share.need_email',
          "Enter the doctor or researcher's email"));
      return;
    }
    setState(() => _busy = true);
    final err =
        await widget.appState.shareChildWithClinician(_childId, email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      _email.clear();
      _snack('✅ ${t('flutter.share.granted', 'Access granted')}');
      await _loadShares();
    } else {
      _snack('⚠️ $err');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final kids = widget.appState.children;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            t('flutter.share.title', 'Share with a doctor'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GsColors.surface,
              borderRadius: BorderRadius.circular(GsRadius.md),
              border: Border.all(color: GsColors.border),
              boxShadow: gsShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    t('flutter.share.sub',
                        'Grant a GrowSense Doctor or Researcher account read access to one child — growth data only, never your account details. Revoke anytime.'),
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: GsColors.text2,
                        height: 1.5)),
                const SizedBox(height: 12),

                // Child selector chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kids)
                      ChoiceChip(
                        label: Text(c['name'] as String? ?? '',
                            style: const TextStyle(fontSize: 12)),
                        selected: _childId == c['child_id'],
                        onSelected: (_) {
                          setState(() => _childId = c['child_id']);
                          _loadShares();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _dec(t('flutter.share.email',
                        "Doctor / researcher's account email"))),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _share,
                  child: Text(_busy
                      ? t('flutter.share.sharing', 'Granting…')
                      : t('flutter.share.btn', 'Grant access')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_shares.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GsColors.surface,
                borderRadius: BorderRadius.circular(GsRadius.md),
                border: Border.all(color: GsColors.border),
                boxShadow: gsShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      t('flutter.share.current', 'Who has access'),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GsColors.accent)),
                  const SizedBox(height: 6),
                  for (final s in _shares)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                    (s['user_accounts']
                                            as Map?)?['email'] as String? ??
                                        '—',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    (s['user_accounts'] as Map?)?[
                                            'account_role'] as String? ??
                                        '',
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        color: GsColors.text3)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final err = await widget.appState
                                  .revokeShare(s['assignment_id']);
                              if (err == null) {
                                _snack(
                                    '✅ ${t('flutter.share.revoked', 'Access revoked')}');
                                await _loadShares();
                              } else {
                                _snack('⚠️ $err');
                              }
                            },
                            child: Text(
                                t('flutter.share.revoke', 'Revoke'),
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: GsColors.flag)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration _dec(String label) =>
    InputDecoration(labelText: label, isDense: true);
