import 'package:flutter/material.dart';

import '../theme.dart';

/// Stand-in for tabs not yet ported from the PWA.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(
      {super.key, required this.title, required this.note});
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(note,
              style: const TextStyle(fontSize: 13, color: GsColors.text3)),
        ],
      ),
    );
  }
}
