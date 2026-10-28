import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';

/// Impostazioni: lingua (immediata e persistente), account SIP (più PBX),
/// casella vocale, log di debug. Le password SIP vanno solo allo storage sicuro.
class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  late final _vmCode = TextEditingController(
    text: widget.phone.settings.voicemailCode,
  );
  late bool _debug = widget.phone.settings.debugLog;

  PhoneController get p => widget.phone;

  @override
  void dispose() {
    _vmCode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_vmCode.text.trim().isNotEmpty) await p.setVoicemailCode(_vmCode.text);
    await p.setDebugLog(_debug);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _section(
    DrinColors c,
    IconData icon,
    String title, {
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: c.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _accountTile(DrinColors c, SipAccount a) {
    final reg = p.registrations[a.id]?.status;
    final (dot, state) = switch (reg) {
      RegistrationStatus.ok => (c.ok, tr('Registrato')),
      RegistrationStatus.progress => (c.ringing, tr('Registrazione…')),
      RegistrationStatus.failed => (c.busy, tr('Errore registrazione')),
      _ => (c.muted, tr('Non registrato')),
    };
    final pbx = p.connectionOf(a)?.label;
    final primary = a.id == p.settings.account?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Tooltip(
            message: state,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.displayName.isNotEmpty
                            ? '${a.displayName} · ${a.username}'
                            : a.username,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                    if (primary) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.keyBtn,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tr('Principale'),
                          style: TextStyle(fontSize: 11, color: c.accent),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    '${a.domain} · ${a.transport.name.toUpperCase()}',
                    pbx == null ? tr('nessun PBX collegato') : 'PBX: $pbx',
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Modifica'),
            onPressed: () => _edit(a),
            icon: Icon(Icons.edit_outlined, size: 18, color: c.muted),
          ),
          IconButton(
            tooltip: tr('Rimuovi account'),
            onPressed: () async {
              await p.removeAccount(a.id);
              setState(() {});
            },
            icon: Icon(Icons.delete_outline, size: 18, color: c.busyText),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(SipAccount? a) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AccountEditor(phone: p, account: a),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(tr('Impostazioni')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Lingua: si applica subito, senza Salva.
              _section(c, Icons.translate_rounded, tr('Lingua')),
              SegmentedButton<AppLang>(
                segments: [
                  for (final l in AppLang.values)
                    ButtonSegment(value: l, label: Text(l.label)),
                ],
                selected: {appLang.value},
                onSelectionChanged: (s) async {
                  await p.setLanguage(s.first);
                  setState(() {});
                },
              ),
              _section(
                c,
                Icons.sip_outlined,
                tr('Account SIP'),
                action: TextButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('Aggiungi account')),
                ),
              ),
              if (p.settings.accounts.isEmpty)
                Text(
                  tr('Nessun account SIP configurato.'),
                  style: TextStyle(color: c.muted),
                ),
              for (final a in p.settings.accounts) _accountTile(c, a),
              Text(
                tr(
                  'Il primo account è il principale. Ogni account chiama e '
                  'segue in BLF gli interni del PBX collegato.',
                ),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              _section(c, Icons.voicemail_rounded, tr('Casella vocale')),
              TextField(
                controller: _vmCode,
                style: mono(c.text),
                decoration: InputDecoration(
                  labelText: tr('Codice per ascoltare i messaggi'),
                  helperText: tr('Yeastar P-Series: *2 (verifica sul tuo PBX)'),
                ),
              ),
              _section(c, Icons.bug_report_outlined, tr('Diagnostica')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _debug,
                onChanged: (v) => setState(() => _debug = v ?? false),
                title: Text(tr('Log di debug del motore SIP')),
                subtitle: Text(
                  tr('Attivo dal prossimo avvio. File in {d}', {'d': p.logDir}),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Chiudi')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Salva'))),
      ],
    );
  }
}

/// Aggiunta o modifica di un account SIP, con il PBX a cui appartiene.
class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.phone, this.account});
  final PhoneController phone;
  final SipAccount? account;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.displayName);
  late final _user = TextEditingController(text: widget.account?.username);
  late final _password = TextEditingController(text: widget.account?.password);
  late final _domain = TextEditingController(text: widget.account?.domain);
  late SipTransport _transport = widget.account?.transport ?? SipTransport.udp;
  late String _pbxId = widget.account?.pbxId ?? '';

  @override
  void dispose() {
    for (final c in [_name, _user, _password, _domain]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Obbligatorio') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await widget.phone.saveAccount(
      SipAccount(
        id: widget.account?.id ?? widget.phone.newAccountId(),
        pbxId: _pbxId,
        username: _user.text.trim(),
        password: _password.text,
        domain: _domain.text.trim(),
        transport: _transport,
        displayName: _name.text.trim(),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final conns = widget.phone.connections;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        widget.account == null ? tr('Aggiungi account') : tr('Account SIP'),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: tr('Nome visualizzato')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                validator: _required,
                decoration: InputDecoration(labelText: tr('Utente / interno')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                validator: _required,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Password')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _domain,
                validator: _required,
                decoration: InputDecoration(
                  labelText: tr('Server SIP'),
                  hintText: tr('pbx.esempio.it oppure 192.168.1.10:5060'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SipTransport>(
                initialValue: _transport,
                decoration: InputDecoration(labelText: tr('Trasporto')),
                items: [
                  for (final t in SipTransport.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t.name.toUpperCase()),
                    ),
                ],
                onChanged: (t) => setState(() => _transport = t!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: conns.any((x) => x.id == _pbxId) ? _pbxId : '',
                decoration: InputDecoration(
                  labelText: tr('PBX collegato'),
                  helperText: tr(
                    'I suoi interni si chiamano con questo account',
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(tr('Automatico (stesso host)')),
                  ),
                  for (final x in conns)
                    DropdownMenuItem(value: x.id, child: Text(x.label)),
                ],
                onChanged: (v) => setState(() => _pbxId = v ?? ''),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Annulla')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Salva e registra'))),
      ],
    );
  }
}
