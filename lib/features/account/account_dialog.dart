import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';

/// Impostazioni account SIP. La password va solo allo storage sicuro.
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
  late SipTransport _transport =
      widget.phone.settings.account?.transport ?? SipTransport.udp;
  late bool _debug = widget.phone.settings.debugLog;

  @override
  void dispose() {
    for (final c in [_name, _user, _password, _domain]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hasAccount = widget.phone.settings.account != null;
    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Account SIP'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome visualizzato',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Utente / interno',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                validator: _required,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _domain,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Server SIP',
                  hintText: 'pbx.esempio.it oppure 192.168.1.10:5060',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SipTransport>(
                initialValue: _transport,
                decoration: const InputDecoration(labelText: 'Trasporto'),
                items: [
                  for (final t in SipTransport.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t.name.toUpperCase()),
                    ),
                ],
                onChanged: (t) => setState(() => _transport = t!),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _debug,
                onChanged: (v) => setState(() => _debug = v ?? false),
                title: const Text('Log di debug del motore SIP'),
                subtitle: Text(
                  'Attivo dal prossimo avvio. File in ${widget.phone.logDir}',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
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
            child: Text('Rimuovi account', style: TextStyle(color: c.busyText)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salva e registra')),
      ],
    );
  }
}
