import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config.dart';
import '../../theme.dart';
import '../../providers.dart';
import '../../screens/ghost_rules_screen.dart';
import '../../widgets/ghost_bottom_sheet.dart';
import '../../widgets/map_provider_picker.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final groups = ref.watch(groupProvider);
    final location = ref.watch(locationProvider);
    final name = auth.displayName ?? 'User';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Profile card
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: PointColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: context.primaryText,
                          ),
                        ),
                        Text(
                          auth.userId ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (auth.isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x143F51FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: PointColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats
              Row(
                children: [
                  _statBox(context, '${groups.groups.length}', 'Groups'),
                  const SizedBox(width: 8),
                  _statBoxAccent(Icons.location_on_rounded, 'Sharing'),
                ],
              ),
            ],
          ),
        ),

        // Sharing controls
        Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 20,
                        color: location.isSharing ? PointColors.online : context.secondaryText),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(location.isSharing ? 'Sharing Location' : 'Not Sharing',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.primaryText)),
                        Text('${groups.groups.length} groups, ${ref.watch(sharingProvider).shares.length} people',
                            style: TextStyle(fontSize: 11, color: context.secondaryText)),
                      ],
                    )),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: location.isSharing ? PointColors.online : context.tertiaryText,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: context.dividerClr,
                indent: 16,
                endIndent: 16,
              ),
              Builder(builder: (context) {
                final ghost = ref.watch(ghostProvider);
                return Column(children: [
              _toggleRow(
                context,
                Icons.visibility_off_rounded,
                'Ghost Mode',
                ghost.activeRules.isEmpty
                    ? 'Tap to set up schedules & rules'
                    : '${ghost.activeRules.length} active rule${ghost.activeRules.length == 1 ? '' : 's'}',
                ghost.isGhostActive || location.isGhostMode,
                onChanged: (_) => GhostBottomSheet.show(context),
              ),
              // Ghost rules link
              Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: const SizedBox(width: 24),
                  title: Text('Edit Ghost Rules',
                      style: TextStyle(fontSize: 13, color: PointColors.accent, fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: context.secondaryText),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GhostRulesScreen())),
                ),
              ),
                ]); }),
            ],
          ),
        ),

        // Server
        _sectionLabel(context, 'Server'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              _infoRow(
                context,
                Icons.dns_rounded,
                AppConfig.serverUrl.replaceAll('http://', ''),
                badge: 'CONNECTED',
                badgeColor: PointColors.online,
              ),
              _divider(context),
              _actionRow(context, Icons.link_rounded, 'Generate Invite', onTap: () => _generateInvite(context, ref)),
            ],
          ),
        ),

        // App
        _sectionLabel(context, 'App'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Builder(
            builder: (context) {
              final themeState = ref.watch(themeProvider);
              final modeLabel = themeState.mode == ThemeMode.dark
                  ? 'Dark'
                  : themeState.mode == ThemeMode.light
                  ? 'Light'
                  : 'System';
              return Column(
                children: [
                  InkWell(
                    onTap: () {
                      final next = themeState.mode == ThemeMode.system
                          ? ThemeMode.light
                          : themeState.mode == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.system;
                      ref.read(themeProvider.notifier).setMode(next);
                    },
                    child: _settingRow(context, Icons.dark_mode_rounded, 'Dark Mode', modeLabel),
                  ),
                  _divider(context),
                  InkWell(
                    onTap: () => MapProviderPicker.show(context),
                    child: _settingRow(context, Icons.map_rounded, 'Map Provider', AppConfig.mapProvider.label),
                  ),
                  _divider(context),
                  InkWell(
                    onTap: () => _showPushProviderSheet(context),
                    child: _settingRow(context, Icons.notifications_rounded, 'Push Notifications', AppConfig.pushProvider.label),
                  ),
                  _divider(context),
                  InkWell(
                    onTap: () => _showChangePasswordSheet(context, ref),
                    child: _settingRow(context, Icons.key_rounded, 'Change Password', ''),
                  ),
                ],
              );
            },
          ),
        ),

        // Sign out
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('You will stop sharing your location.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'Sign Out',
                        style: TextStyle(color: PointColors.danger),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                ref.read(authProvider.notifier).logout();
              }
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 20, 14, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'Sign Out',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: PointColors.danger,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Delete account
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDeleteAccountDialog(context, ref),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x0AFF3B30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'Delete Account',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: PointColors.danger,
                  ),
                ),
              ),
            ),
          ),
        ),

        Center(
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              return Text(
                'Point v$version',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: context.tertiaryText,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _statBox(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: context.subtleBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: context.primaryText,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: context.secondaryText,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBoxAccent(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x0A00E676),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: PointColors.online),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: PointColors.online,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    bool value, {
    ValueChanged<bool>? onChanged,
  }) {
    return Semantics(
      toggled: value,
      label: '$title: $subtitle',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.primaryText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeColor: PointColors.accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: context.tertiaryText,
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String value, {
    String? badge,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.secondaryText),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.secondaryText,
            ),
          ),
          if (badge != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (badgeColor ?? PointColors.accent).withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: badgeColor ?? PointColors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, IconData icon, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: context.primaryText),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.primaryText,
              ),
            ),
            const Spacer(),
            Text('\u203A', style: TextStyle(color: context.tertiaryText)),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.primaryText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.primaryText,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(fontSize: 12, color: context.secondaryText),
            ),
          const SizedBox(width: 4),
          Text('\u203A', style: TextStyle(color: context.tertiaryText)),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: context.dividerClr, indent: 16, endIndent: 16);

  void _showPushProviderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          var selected = AppConfig.pushProvider;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: context.dividerClr, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Push Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.primaryText)),
                const SizedBox(height: 4),
                Text('How should Point wake your device for updates?',
                    style: TextStyle(fontSize: 12, color: context.secondaryText)),
                const SizedBox(height: 16),
                ...PushProvider.values.map((provider) {
                  final isSelected = selected == provider;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setSheetState(() => selected = provider),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? PointColors.accent.withValues(alpha: 0.08) : context.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? PointColors.accent.withValues(alpha: 0.4) : context.dividerClr,
                            width: isSelected ? 2 : 1,
                          ),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(provider.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.primaryText)),
                                if (provider == PushProvider.unified) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00FF88).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('NO GOOGLE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF00FF88))),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(provider.description, style: TextStyle(fontSize: 11, color: context.secondaryText)),
                            ],
                          )),
                          if (isSelected) const Icon(Icons.check_circle, color: PointColors.accent, size: 22),
                        ],
                      ),
                    ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                if (selected == PushProvider.none)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB700).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Without push, location updates only arrive when you open the app.',
                        style: TextStyle(fontSize: 11, color: context.secondaryText)),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await AppConfig.setPushProvider(selected);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: PointColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(selected == AppConfig.pushProvider ? 'Done' : 'Save & Restart App',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context, WidgetRef ref) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PointColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (newCtrl.text != confirmCtrl.text) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')),
                  );
                  return;
                }
                if (newCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('New password cannot be empty'),
                    ),
                  );
                  return;
                }
                try {
                  await ref.read(authProvider.notifier).changePassword(
                    currentCtrl.text,
                    newCtrl.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password changed')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              child: const Text(
                'Change Password',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action is permanent and cannot be undone. Enter your password to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (passwordCtrl.text.isEmpty) return;
              try {
                await ref.read(authProvider.notifier).deleteAccount(
                  passwordCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) ref.read(authProvider.notifier).logout();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: PointColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _generateInvite(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(authProvider.notifier).createInvite(maxUses: 10);
      final code = result['code'];
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Invite Code'),
            content: SelectableText(
              code ?? '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
