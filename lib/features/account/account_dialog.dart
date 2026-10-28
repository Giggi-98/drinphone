import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';

/// Impostazioni: lingua (immediata e persistente), account SIP, casella vocale,
/// log di debug. La password SIP va solo allo storage sicuro.
class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.phone.settings.account?.displayName,
  );
  late final _user = TextEditingController(
    text: widget.phone.settings.account?.username,
  );
  late final _password = TextEditingController(
    text: widget.phone.settings.account?.password,
  );
  late final _domain = TextEditingController(
    text: widget.phone.settings.account?.domain,
  );
  late final _vmCode = TextEditingController(
    text: widget.phone.settings.voicemailCode,
  );
  late SipTransport _transport =
      widget.phone.settings.account?.transport ?? SipTransport.udp;
  late bool _debug = widget.phone.settings.debugLog;

  @override
  void dispose() {
    for (final c in [_name, _user, _password, _domain, _vmCode]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Obbligatorio') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await widget.phone.setVoicemailCode(_vmCode.text);
    await widget.phone.saveAccount(
      SipAccount(
        username: _user.text.trim(),
        password: _password.text,
        domain: _domain.text.trim(),
        transport: _transport,
        displayName: _name.text.trim(),
      ),
      debugLog: _debug,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _section(DrinColors c, IconData icon, String title) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: c.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hasAccount = widget.phone.settings.account != null;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(tr('Impostazioni')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
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
                    await widget.phone.setLanguage(s.first);
                    setState(() {});
                  },
                ),
                _section(c, Icons.sip_outlined, tr('Account SIP')),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: tr('Nome visualizzato'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _user,
                  validator: _required,
                  decoration: InputDecoration(
                    labelText: tr('Utente / interno'),
                  ),
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
                _section(c, Icons.voicemail_rounded, tr('Casella vocale')),
                TextFormField(
                  controller: _vmCode,
                  validator: _required,
                  style: mono(c.text),
                  decoration: InputDecoration(
                    labelText: tr('Codice per ascoltare i messaggi'),
                    helperText: tr(
                      'Yeastar P-Series: *2 (verifica sul tuo PBX)',
                    ),
                  ),
                ),
                _section(c, Icons.bug_report_outlined, tr('Diagnostica')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _debug,
                  onChanged: (v) => setState(() => _debug = v ?? false),
                  title: Text(tr('Log di debug del motore SIP')),
                  subtitle: Text(
                    tr('Attivo dal prossimo avvio. File in {d}', {
                      'd': widget.phone.logDir,
                    }),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (hasAccount)
          TextButton(
            onPressed: () async {
              await widget.phone.removeAccount();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              tr('Rimuovi account'),
              style: TextStyle(color: c.busyText),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Chiudi')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Salva e registra'))),
      ],
    );
  }
}
