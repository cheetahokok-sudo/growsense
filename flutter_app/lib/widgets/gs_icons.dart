// ══════════════════════════════════════════════════════════════════
// GrowSense icon system — original duotone-line glyphs on a 24px grid.
// Deep-green primary, pale-mint fill plane, sage second tone, with
// semantic accents (teal / crimson / lilac / gold). Light-theme only
// (the app has no dark mode). Rendered via flutter_svg.
//
// Device "form" glyphs (fitbit/whoop/apple/garmin/phone) are generic
// hardware silhouettes — NOT brand logos. Official brand badges are
// added separately, per each brand's guidelines.
//
// Use GsIcon('name') for the glyph, or GsIconTile('name') for the glyph
// on a soft rounded tile (the premium list-row treatment).
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const Map<String, String> _gsIcons = {
  'add':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><circle cx="9.3" cy="8" r="3.6" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M3.5 20.4a5.9 5.9 0 0 1 11.6 0Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><circle cx="18" cy="6.3" r="3.1" fill="#2f7d74"/><path d="M18 4.9v2.8M16.6 6.3h2.8" stroke="#fff" stroke-width="1.4"/></svg>',
  'premium':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M5.6 16.6 5 9l3.8 3.4L12 7l3.2 5.4L19 9l-.6 7.6Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M6 19h12" stroke="#153a2b" stroke-width="1.4"/><circle cx="12" cy="12.5" r="1.25" fill="#b98d3e"/></svg>',
  'share':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M6.9 4.9V9a3.1 3.1 0 0 0 6.2 0V4.9M10 12.1c0 3 2.1 4.4 4.5 4.6" stroke="#153a2b" stroke-width="1.5"/><circle cx="16.8" cy="16.9" r="2.4" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><circle cx="16.8" cy="16.9" r=".9" fill="#2f7d74"/><circle cx="6.9" cy="4.7" r="1" fill="#2f7d74"/><circle cx="13.1" cy="4.7" r="1" fill="#2f7d74"/></svg>',
  'bell':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.4a1.3 1.3 0 0 0-1.3 1.3v.35A4.6 4.6 0 0 0 7.4 9.7c0 3.1-.95 4.3-1.55 5.1a.7.7 0 0 0 .56 1.12h11.18a.7.7 0 0 0 .56-1.12c-.6-.8-1.55-2-1.55-5.1a4.6 4.6 0 0 0-3.3-4.35v-.35A1.3 1.3 0 0 0 12 3.4Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M9.8 17.5a2.2 2.2 0 0 0 4.4 0" fill="none" stroke="#78a488" stroke-width="1.5"/></svg>',
  'notif':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.4a1.3 1.3 0 0 0-1.3 1.3v.35A4.6 4.6 0 0 0 7.4 9.7c0 3.1-.95 4.3-1.55 5.1a.7.7 0 0 0 .56 1.12h11.18a.7.7 0 0 0 .56-1.12c-.6-.8-1.55-2-1.55-5.1v-.2" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M9.8 17.5a2.2 2.2 0 0 0 4.4 0" stroke="#78a488" stroke-width="1.5"/><circle cx="17.4" cy="6" r="2.5" fill="#a23b3b"/></svg>',
  'csv':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M13 3.6H7.6A1.6 1.6 0 0 0 6 5.2v13.6A1.6 1.6 0 0 0 7.6 20.4h8.8A1.6 1.6 0 0 0 18 18.8V8.6Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M13 3.6V8.6H18" stroke="#153a2b" stroke-width="1.4"/><path d="M12 11.4v5M9.9 14.3 12 16.4 14.1 14.3" stroke="#2f7d74" stroke-width="1.5"/></svg>',
  'pdf':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M13 3.6H7.6A1.6 1.6 0 0 0 6 5.2v13.6A1.6 1.6 0 0 0 7.6 20.4h8.8A1.6 1.6 0 0 0 18 18.8V8.6Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M13 3.6V8.6H18" stroke="#153a2b" stroke-width="1.4"/><path d="M12 17c-2.1-1.3-3.2-2.4-3.2-3.8a1.7 1.7 0 0 1 3.2-.85 1.7 1.7 0 0 1 3.2.85c0 1.4-1.1 2.5-3.2 3.8Z" fill="#a23b3b"/></svg>',
  'about':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20.5V10.8" stroke="#153a2b" stroke-width="1.4"/><path d="M12 13.4c-4 0-6.2-2.2-6.2-6.2 4 0 6.2 2.2 6.2 6.2Z" fill="#78a488"/><path d="M12 11.6c0-3.6 2-5.8 5.6-5.8 0 3.6-2 5.8-5.6 5.8Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.3"/></svg>',
  'support':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 13.3v-1.1a6.5 6.5 0 0 1 13 0v1.1" stroke="#153a2b" stroke-width="1.5"/><rect x="3.9" y="12.8" width="3" height="5.4" rx="1.4" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><rect x="17.1" y="12.8" width="3" height="5.4" rx="1.4" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M18.6 18.2v.5a2.3 2.3 0 0 1-2.3 2.3H13.4" stroke="#2f7d74" stroke-width="1.4"/></svg>',
  'privacy':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.6 5.6 6.1v5c0 4.1 2.7 7.1 6.4 8.3 3.7-1.2 6.4-4.2 6.4-8.3v-5Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M9.2 11.9 11.1 13.8 14.9 9.8" stroke="#2f7d74" stroke-width="1.7"/></svg>',
  'billing':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="6" width="17" height="12" rx="2.6" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M3.5 10h17" stroke="#153a2b" stroke-width="1.4"/><rect x="6" y="13.2" width="4.2" height="2.5" rx=".7" fill="#b98d3e"/></svg>',
  'home':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M4.2 11.4 12 4.4l7.8 7v8.2a.6.6 0 0 1-.6.6H4.8a.6.6 0 0 1-.6-.6Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M10 20.2v-4.4a2 2 0 0 1 4 0v4.4" fill="#78a488"/></svg>',
  'insights':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M5 15l4-4 3 2 6.2-6.4V19H5Z" fill="#cfe3d5"/><path d="M5 15l4-4 3 2 6.2-6.4" stroke="#153a2b" stroke-width="1.5"/><path d="M4 19.2h16" stroke="#153a2b" stroke-width="1.4"/><circle cx="18.2" cy="6.6" r="1.3" fill="#2f7d74"/></svg>',
  'account':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="3.7" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M5.4 20.2a6.6 6.6 0 0 1 13.2 0Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/></svg>',
  'settings':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.6h4.6M13.4 8.6H20" stroke="#153a2b" stroke-width="1.5"/><path d="M4 15.4h6.6M15.4 15.4H20" stroke="#153a2b" stroke-width="1.5"/><circle cx="11" cy="8.6" r="2.3" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><circle cx="13" cy="15.4" r="2.3" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/></svg>',
  'more':
      '<svg viewBox="0 0 24 24"><circle cx="6" cy="12" r="1.7" fill="#153a2b"/><circle cx="12" cy="12" r="1.7" fill="#153a2b"/><circle cx="18" cy="12" r="1.7" fill="#78a488"/></svg>',
  'chevron':
      '<svg viewBox="0 0 24 24" fill="none" stroke="#153a2b" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 5.5 16 12l-6.5 6.5"/></svg>',
  'watch':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="9.4" y="3.5" width="5.2" height="5.8" rx="1.9" fill="#cfe3d5"/><rect x="9.4" y="14.7" width="5.2" height="5.8" rx="1.9" fill="#cfe3d5"/><rect x="6.9" y="6.9" width="10.2" height="10.2" rx="3" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M9.6 12.3h1.3l.8-1.9 1 3.2.8-1.5h1.2" stroke="#2f7d74" stroke-width="1.4"/></svg>',
  'ring':
      '<svg viewBox="0 0 24 24"><path fill-rule="evenodd" d="M12 6.5a6.1 6.1 0 1 0 0 12.2 6.1 6.1 0 0 0 0-12.2Zm0 3.4a2.7 2.7 0 1 1 0 5.4 2.7 2.7 0 0 1 0-5.4Z" fill="#d0e6e1" stroke="#2f7d74" stroke-width="1.3"/><circle cx="12" cy="6.2" r="1.5" fill="#2f7d74"/></svg>',
  'phone':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="3.5" width="10" height="17" rx="2.6" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M10.4 6h3.2" stroke="#153a2b" stroke-width="1.2"/><path d="M12 12.6c-1.3-.85-2-1.6-2-2.4a1.05 1.05 0 0 1 2-.55 1.05 1.05 0 0 1 2 .55c0 .8-.7 1.55-2 2.4Z" fill="#a23b3b"/><circle cx="12" cy="17.9" r=".85" fill="#2f7d74"/></svg>',
  'gluc':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4c3 3.9 5 6.1 5 8.7a5 5 0 0 1-10 0C7 10.1 9 7.9 12 4Z" fill="#f4dcdc" stroke="#a23b3b" stroke-width="1.4"/><circle cx="12" cy="12.7" r="2.2" fill="none" stroke="#a23b3b" stroke-width="1.3"/><circle cx="12" cy="12.7" r=".85" fill="#a23b3b"/></svg>',
  'eeg':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M5 14.4V13a7 7 0 0 1 14 0v1.4a1.1 1.1 0 0 1-2.2 0V13a4.8 4.8 0 0 0-9.6 0v1.4a1.1 1.1 0 0 1-2.2 0Z" fill="#e3def1" stroke="#6f6da8" stroke-width="1.3"/><path d="M8 12.6 9.3 11l1.4 3 1.3-3 1.4 3 1.2-2.2" stroke="#6f6da8" stroke-width="1.4"/></svg>',
  'form_band':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="10.2" y="3" width="3.6" height="4.6" rx="1.5" fill="#cfe3d5"/><rect x="10.2" y="16.4" width="3.6" height="4.6" rx="1.5" fill="#cfe3d5"/><rect x="8.6" y="6" width="6.8" height="12" rx="3.2" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M10.3 12h.9l.6-1.5.9 2.8.6-1.3h1" stroke="#2f7d74" stroke-width="1.3"/></svg>',
  'form_loop':
      '<svg viewBox="0 0 24 24" fill-rule="evenodd"><path d="M12 4.4c-3.9 0-6.4 3-6.4 7.6s2.5 7.6 6.4 7.6 6.4-3 6.4-7.6-2.5-7.6-6.4-7.6Zm0 3.1c2.1 0 3.5 1.9 3.5 4.5s-1.4 4.5-3.5 4.5-3.5-1.9-3.5-4.5 1.4-4.5 3.5-4.5Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.3"/><circle cx="12" cy="4.5" r="1.4" fill="#2f7d74"/></svg>',
  'form_squircle':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="9.3" y="3" width="5.4" height="4.6" rx="1.9" fill="#cfe3d5"/><rect x="9.3" y="16.4" width="5.4" height="4.6" rx="1.9" fill="#cfe3d5"/><rect x="6.6" y="6.2" width="10.8" height="11.6" rx="3.6" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M18 10.4v3" stroke="#153a2b" stroke-width="1.6"/><path d="M12 14c-1.4-.9-2.1-1.7-2.1-2.6a1.1 1.1 0 0 1 2.1-.6 1.1 1.1 0 0 1 2.1.6c0 .9-.7 1.7-2.1 2.6Z" fill="#a23b3b"/></svg>',
  'form_round':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M9.6 7.2 10 3.7h4l.4 3.5M9.6 16.8 10 20.3h4l.4-3.5" fill="#cfe3d5"/><circle cx="12" cy="12" r="5.4" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M17.5 10.4v.6M17.5 13v.6" stroke="#153a2b" stroke-width="1.7"/><circle cx="12" cy="12" r="1.6" fill="none" stroke="#2f7d74" stroke-width="1.3"/></svg>',
  'ai':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M11 3.8l1.5 4.7 4.7 1.5-4.7 1.5L11 16.2l-1.5-4.7L4.8 10l4.7-1.5Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.3"/><path d="M17.4 14l.55 1.7 1.7.55-1.7.55-.55 1.7-.55-1.7-1.7-.55 1.7-.55Z" fill="#2f7d74"/></svg>',
  'bone':
      '<svg viewBox="0 0 24 24" fill="#153a2b"><g transform="rotate(-45 12 12)"><rect x="6.2" y="10.2" width="11.6" height="3.6" rx="1.1"/><circle cx="6.8" cy="9.4" r="2.55"/><circle cx="6.8" cy="14.6" r="2.55"/><circle cx="17.2" cy="9.4" r="2.55"/><circle cx="17.2" cy="14.6" r="2.55"/></g></svg>',
  'lab':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 3.6h5" stroke="#153a2b" stroke-width="1.4"/><path d="M10 3.6v13.4a2 2 0 0 0 4 0V3.6" stroke="#153a2b" stroke-width="1.4"/><path d="M10 11h4v6a2 2 0 0 1-4 0Z" fill="#cfe3d5"/><circle cx="11.3" cy="14" r=".65" fill="#2f7d74"/></svg>',
  'measure':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><rect x="8" y="3.5" width="8" height="17" rx="2" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M8 7.2h3M8 10.8h2M8 14.4h3M8 18h2" stroke="#153a2b" stroke-width="1.3"/></svg>',
  'illness':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4.5a2 2 0 0 0-2 2v7.4a3.3 3.3 0 1 0 4 0V6.5a2 2 0 0 0-2-2Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><circle cx="12" cy="16.7" r="2" fill="#a23b3b"/><path d="M12 8.2v6" stroke="#a23b3b" stroke-width="1.6"/></svg>',
  'ticket':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 7H18.5a1.5 1.5 0 0 1 1.5 1.5V10a1.7 1.7 0 0 0 0 3.8V15.5a1.5 1.5 0 0 1-1.5 1.5H5.5a1.5 1.5 0 0 1-1.5-1.5V13.8a1.7 1.7 0 0 0 0-3.8V8.5a1.5 1.5 0 0 1 1.5-1.5Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.4"/><path d="M14.6 7.6V16.4" stroke="#2f7d74" stroke-width="1.2" stroke-dasharray="1.3 1.5"/></svg>',
  'sprout':
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20v-6" stroke="#153a2b" stroke-width="1.4"/><path d="M12 15c-3 0-4.5-1.5-4.5-4.5 3 0 4.5 1.5 4.5 4.5Z" fill="#78a488"/><path d="M12 13c0-2.6 1.5-4 4-4 0 2.6-1.5 4-4 4Z" fill="#cfe3d5" stroke="#153a2b" stroke-width="1.3"/><path d="M8 20h8" stroke="#153a2b" stroke-width="1.4"/></svg>',
};

/// Soft tile tint per icon (defaults to pale green). Device categories
/// carry their semantic tint.
const Map<String, Color> _gsIconTint = {
  'ring': Color(0xFFE6F2EE),
  'phone': Color(0xFFE6F2EE),
  'form_round': Color(0xFFE6F2EE),
  'gluc': Color(0xFFFAEDED),
  'eeg': Color(0xFFEFEDF8),
};
const Color _gsTileDefault = Color(0xFFEDF3EE);

/// A single GrowSense glyph at [size] px.
class GsIcon extends StatelessWidget {
  const GsIcon(this.name, {super.key, this.size = 24});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final svg = _gsIcons[name];
    if (svg == null) return SizedBox(width: size, height: size);
    return SvgPicture.string(svg, width: size, height: size);
  }
}

/// A glyph centered on a soft rounded tile — the premium list-row look.
class GsIconTile extends StatelessWidget {
  const GsIconTile(this.name,
      {super.key, this.tile = 36, this.glyph = 22, this.tint});
  final String name;
  final double tile;
  final double glyph;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tile,
      height: tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint ?? _gsIconTint[name] ?? _gsTileDefault,
        borderRadius: BorderRadius.circular(tile * 0.3),
      ),
      child: GsIcon(name, size: glyph),
    );
  }
}
