import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/api_credential_store.dart';

/// Integrazione Yeastar OpenAPI. Client ID e Secret sono di sola scrittura:
/// i campi partono sempre vuoti e non esiste un modo per rileggerli dalla UI.
class ApiDialog extends StatefulWidget {
  const ApiDialog({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<ApiDialog> createState() => _ApiDialogState();
}

class _ApiDialogState extends State<ApiDialog> {
  final _form = GlobalKey<FormState>();
  late final _baseUrl = TextEditingController(
    text:
        'https://${widget.phone.settings.account?.domain.split(':').first ?? ''}',
  );
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_baseUrl, _clientId, _clientSecret]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateUrl(String? v) {
    final u = Uri.tryParse(v?.trim() ?? '');
    if (u == null || u.host.isEmpty) return 'URL non valido';
    if (u.scheme != 'https') return 'Serve https://';
    return null;
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.phone.saveApiCredentials(
      ApiCredentials(
        baseUrl: _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
        clientId: _clientId.text.trim(),
        clientSecret: _clientSecret.text.trim(),
      ),
    );
    _clientId.clear();
    _clientSecret.clear();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final hint = p.apiConfigured
        ? 'Impostato · scrivi per sostituire'
        : 'Da Integrations > API sul PBX';
    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Integrazione PBX Yeastar (API)'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                p.apiStatus ?? 'Non configurata',
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrl,
                validator: _validateUrl,
                decoration: const InputDecoration(
                  labelText: 'Indirizzo API del PBX',
                  hintText:
                      'https://pbx.esempio.it oppure https://10.0.0.5:8088',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientId,
                validator: _required,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Client ID',
                  hintText: hint,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientSecret,
                validator: _required,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Client Secret',
                  hintText: hint,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Accesso amministrativo al PBX: cifrate su questo PC per il '
                'tuo utente Windows, mai mostrate né scritte nei log.',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (p.apiConfigured)
          TextButton(
            onPressed: () async {
              await p.clearApiCredentials();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('Rimuovi', style: TextStyle(color: c.busyText)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Connessione…' : 'Salva e connetti'),
        ),
      ],
    );
  }
}
