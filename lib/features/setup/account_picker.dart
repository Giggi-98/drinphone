import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/settings_store.dart';
import 'setup_wizard.dart';

/// Scelta dell'account (DECISIONS "Un account vivo alla volta"): all'avvio
/// con più account e nessun predefinito, e dopo il logout. Da qui si entra,
/// si sceglie il predefinito, si aggiunge, rinomina o elimina un account.
class AccountPicker extends StatelessWidget {
  const AccountPicker({super.key, required this.phone});
  final PhoneController phone;

  void _add(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => SetupWizard(
        phone: phone,
        firstRun: false,
        onDone: () => Navigator.of(ctx).pop(),
      ),
    ),
  );

  Future<void> _rename(BuildContext context, Profile a) async {
    final ctl = TextEditingController(text: a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rinomina account')),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(tr('Salva')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (name != null) await phone.renameAccount(a.id, name);
  }

  Future<void> _delete(BuildContext context, Profile a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminare l’account {n}?', {'n': a.name})),
        content: Text(
          tr(
            'Si cancellano la registrazione SIP, le credenziali API, il '
            'registro chiamate e i contatti personali dell’account.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Elimina')),
          ),
        ],
      ),
    );
    if (ok == true) await phone.deleteProfile(a.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Scaffold(
      backgroundColor: c.ground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListenableBuilder(
              listenable: phone,
              builder: (context, _) {
                final accounts = phone.settings.profiles;
                final def = phone.settings.defaultProfile;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        DrinLogo(height: 40),
                        Spacer(),
                        ChannelBadge(),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      tr('Scegli l’account'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        'Un account alla volta. Quello predefinito si apre da '
                        'solo all’avvio.',
                      ),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 20),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final a in accounts)
                            _AccountRow(
                              account: a,
                              isDefault: a.id == def,
                              onOpen: () => phone.login(a.id),
                              onDefault: () => phone.setDefaultAccount(
                                a.id == def ? '' : a.id,
                              ),
                              onRename: () => _rename(context, a),
                              onDelete: () => _delete(context, a),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _add(context),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(tr('Aggiungi account')),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.isDefault,
    required this.onOpen,
    required this.onDefault,
    required this.onRename,
    required this.onDelete,
  });
  final Profile account;
  final bool isDefault;
  final VoidCallback onOpen;
  final VoidCallback onDefault;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final sip = account.accounts.firstOrNull;
    final yeastar = account.kind == ProfileKind.yeastar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: isDefault ? c.accent : c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  yeastar ? Icons.hub_rounded : Icons.dialpad_rounded,
                  size: 26,
                  color: isDefault ? c.accent : c.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name.isEmpty ? tr('Account') : account.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          sip == null
                              ? tr('Da configurare')
                              : '${sip.username}@${sip.domain}',
                          yeastar ? tr('Yeastar') : tr('SIP generico'),
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isDefault
                      ? tr('Predefinito all’avvio')
                      : tr('Usa come predefinito all’avvio'),
                  onPressed: onDefault,
                  icon: Icon(
                    isDefault
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isDefault ? c.accent : c.muted,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('Altro'),
                  onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(tr('Rinomina…')),
                    ),
                    PopupMenuItem(value: 'delete', child: Text(tr('Elimina…'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
