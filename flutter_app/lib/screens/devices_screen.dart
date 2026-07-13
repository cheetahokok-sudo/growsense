import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../wearables.dart';

/// Devices & sensors — connect wearables and biosensors. Fitbit/Google
/// Health is live (reuses the PWA's Edge Functions); the rest are
/// listed with their planned data contributions so the roadmap is
/// visible and the architecture is obviously extensible.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    widget.appState.loadWearableStatus(force: true);
  }

  Future<void> _connectFitbit() async {
    final t = widget.i18n.t;
    final childId = widget.appState.activeChildId;
    if (childId == null) return;
    final csrf =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    final url = buildFitbitAuthUrl(childId, csrf);
    try {
      await launchUrl(url,
          webOnlyWindowName: '_self', mode: LaunchMode.platformDefault);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('flutter.dev.connect_web',
                'Open the web app to connect this device.'))));
      }
    }
  }

  Future<void> _sync() async {
    final t = widget.i18n.t;
    final (nights, err) = await widget.appState.syncFitbit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
      content: Text(err == null
          ? '✅ ${nights ?? 0} ${t('flutter.dev.nights_synced', 'nights synced')}'
          : '${t('flutter.not_saved', 'Sync failed')}: $err'),
    ));
  }

  Future<void> _disconnect() async {
    final t = widget.i18n.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('flutter.dev.disconnect_title', 'Disconnect Fitbit?')),
        content: Text(t('flutter.dev.disconnect_body',
            'Sleep already synced stays. You can reconnect with any Google account.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('common.cancel', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: GsColors.flag),
              child: Text(t('flutter.dev.disconnect', 'Disconnect'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await widget.appState.disconnectFitbit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
      content: Text(err == null
          ? t('flutter.dev.disconnected', 'Fitbit disconnected')
          : '${t('flutter.not_saved', 'Failed')}: $err'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('flutter.dev.title', 'Devices & sensors'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: widget.appState,
        builder: (context, _) {
          final byCat = <DeviceCategory, List<WearableProvider>>{};
          for (final p in wearableProviders) {
            byCat.putIfAbsent(p.category, () => []).add(p);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                t('flutter.dev.intro',
                    'Connect a wearable so sleep, HRV, and activity flow into the growth model automatically. Sleep quality is the single biggest lever on growth hormone — so a sleep-tracking device is the most valuable to connect.'),
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: GsColors.text2),
              ),
              const SizedBox(height: 16),
              for (final cat in DeviceCategory.values)
                if (byCat[cat] != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text(deviceCategoryLabel[cat] ?? '',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: deviceCategoryColor(cat))),
                  ),
                  for (final p in byCat[cat]!)
                    _ProviderCard(
                      provider: p,
                      i18n: widget.i18n,
                      status: p.id == 'fitbit'
                          ? widget.appState.wearableStatus
                          : null,
                      syncing: widget.appState.syncingWearable,
                      onConnect: p.id == 'fitbit' ? _connectFitbit : null,
                      onSync: p.id == 'fitbit' ? _sync : null,
                      onDisconnect: p.id == 'fitbit' ? _disconnect : null,
                    ),
                  const SizedBox(height: 14),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.i18n,
    required this.status,
    required this.syncing,
    required this.onConnect,
    required this.onSync,
    required this.onDisconnect,
  });
  final WearableProvider provider;
  final I18n i18n;
  final Map<String, dynamic>? status; // fitbit connection status, if any
  final bool syncing;
  final VoidCallback? onConnect;
  final VoidCallback? onSync;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final isLive = provider.status == ProviderStatus.live;
    final connected = status != null;
    final email = status?['google_email'] as String?;
    final lastSync = (status?['last_sync_at'] as String?)?.split('T').first;
    final tokenValid = status?['token_is_valid'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(
            color: connected && tokenValid
                ? GsColors.accent.withValues(alpha: 0.5)
                : GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: provider.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GsRadius.sm),
                ),
                child: Text(provider.emoji,
                    style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.name,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text(provider.vendor,
                        style: const TextStyle(
                            fontSize: 10.5, color: GsColors.text3)),
                  ],
                ),
              ),
              _StatusBadge(
                  isLive: isLive,
                  connected: connected,
                  tokenValid: tokenValid,
                  i18n: i18n),
            ],
          ),
          const SizedBox(height: 8),
          Text(provider.note,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.35, color: GsColors.text2)),
          const SizedBox(height: 8),
          // Stream chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in provider.streams)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: GsColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(bioStreamLabel[s] ?? s.name,
                      style: const TextStyle(
                          fontSize: 9.5, color: GsColors.text2)),
                ),
            ],
          ),
          if (isLive) ...[
            const SizedBox(height: 10),
            if (connected) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 14, color: GsColors.accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        '${email ?? ''}${lastSync != null ? ' · ${t('flutter.dev.last_sync', 'last sync')} $lastSync' : ''}',
                        style: const TextStyle(
                            fontSize: 10.5, color: GsColors.text2),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        side: const BorderSide(color: GsColors.border2),
                        foregroundColor: GsColors.text,
                      ),
                      onPressed: syncing ? null : onSync,
                      child: Text(syncing
                          ? t('flutter.saving', 'Syncing…')
                          : t('flutter.dev.sync_now', 'Sync now')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      foregroundColor: GsColors.flag,
                    ),
                    onPressed: syncing ? null : onDisconnect,
                    child: Text(t('flutter.dev.disconnect', 'Disconnect')),
                  ),
                ],
              ),
            ] else
              ElevatedButton.icon(
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    backgroundColor: provider.brand),
                icon: const Icon(Icons.link, size: 16),
                label: Text(t('flutter.dev.connect', 'Connect')),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.isLive,
      required this.connected,
      required this.tokenValid,
      required this.i18n});
  final bool isLive;
  final bool connected;
  final bool tokenValid;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final (label, color, bg) = !isLive
        ? (
            t('flutter.dev.planned', 'Planned'),
            GsColors.text3,
            GsColors.surface2
          )
        : connected && tokenValid
            ? (
                t('flutter.dev.connected', 'Connected'),
                GsColors.accentDark,
                GsColors.accentLight
              )
            : connected
                ? (
                    t('flutter.dev.reconnect', 'Reconnect'),
                    GsColors.estimatedDark,
                    GsColors.estimatedLight
                  )
                : (
                    t('flutter.dev.available', 'Available'),
                    GsColors.measuredDark,
                    GsColors.measuredLight
                  );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
