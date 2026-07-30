// ══════════════════════════════════════════════════════════════════
// Shared "are you sure?" for destructive actions.
//
// Clinical rows — lab results, measurements, puberty milestones — were
// deleting on a single tap with no confirmation. On a phone, next to a
// list, that is an accidental data loss waiting to happen, and the data
// is a child's medical history that the parent may have transcribed from
// a paper report.
//
// Bone age already did this correctly (bone_age_screen._confirmDelete);
// this is that pattern, extracted so every destructive row shares it.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// Returns true only if the user explicitly confirmed.
///
/// [note] is for consequences that are not obvious from the action — e.g.
/// that deleting a measurement does NOT return a free-tier slot.
Future<bool> confirmDelete(
  BuildContext context, {
  required I18n i18n,
  required String message,
  String? note,
}) async {
  final t = i18n.t;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 13.5)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note,
                style: const TextStyle(fontSize: 11.5, color: GsColors.text3)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t('common.cancel', 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('common.remove', 'Remove'),
              style: const TextStyle(color: GsColors.flag)),
        ),
      ],
    ),
  );
  return ok == true;
}
