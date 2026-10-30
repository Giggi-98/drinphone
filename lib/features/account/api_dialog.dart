import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/pbx_connection.dart';
import '../../core/pbx/pbx_sync.dart';
import '../../core/security/api_credential_store.dart';
import '../../core/security/cdr_db_store.dart';

/// Connessione API al PBX dell'account (al più una), usata in Preferenze >
/// Integrazione PBX e nella procedura guidata.
class PbxConnectionsPanel extends StatelessWidget {
  const PbxConnectionsPanel({super.key, required this.phone});
  final PhoneController phone;

  String _ago(DateTime? t) {
    if (t == null) return tr('mai');
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('alle {t}', {
      't': '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone.connections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              tr('Nessun PBX collegato.'),
              style: TextStyle(color: c.muted),
            ),
          ),
        for (final conn in phone.connections)
          _ConnectionTile(
            phone: phone,
            conn: conn,
            lastSync: _ago(conn.lastSync),
            primary: conn.id == phone.primaryConnection?.id,
          ),
        if (phone.connections.isEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _CredentialsDialog(phone: phone),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr('Collega il PBX')),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.phone,
    required this.conn,
    required this.lastSync,
    required this.primary,
  });
  final PhoneController phone;
  final PbxConnection conn;
  final String lastSync;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: conn.ok ? c.border : c.busy),
        borderRadius: BorderRadius.circular(12),
      ),
      // Le righe (interruttori, sincronizzazione) disegnano l'effetto al clic
      // su un Material: senza, il fondo della scheda lo nasconderebbe.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 20, color: c.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    conn.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
                if (primary)
                  Tooltip(
                    message: tr(
                      'PBX dell\'account SIP: interni chiamabili e in BLF',
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.keyBtn,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tr('Account SIP'),
                        style: TextStyle(fontSize: 11, color: c.accent),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(conn.host, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 4),
            Text(
              '${conn.status} · ${tr('ultima lettura')} $lastSync',
              style: TextStyle(
                fontSize: 12,
                color: conn.ok ? c.okText : c.busyText,
              ),
            ),
            const SizedBox(height: 4),
            // Richiede su PBX: Integrations > API > Advanced Settings >
            // Extension Status Monitor (Call Status, Presence Status).
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: conn.realtime,
              onChanged: (v) => phone.setRealtime(conn, v),
              secondary: Icon(
                Icons.bolt_rounded,
                color: conn.eventsConnected ? c.ok : c.muted,
              ),
              title: Text(tr('Eventi in tempo reale (WebSocket)')),
              subtitle: Text(
                conn.realtime && conn.eventsStatus.isNotEmpty
                    ? conn.eventsStatus
                    : tr('Presenza e stato chiamate istantanei'),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
            _SyncSettings(phone: phone, conn: conn),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  onPressed: conn.syncing
                      ? null
                      : () => phone.resync(only: conn),
                  icon: conn.syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: Text(tr('Sincronizza ora')),
                ),
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        _CredentialsDialog(phone: phone, conn: conn),
                  ),
                  icon: const Icon(Icons.key_outlined, size: 16),
                  label: Text(tr('Credenziali')),
                ),
                if (conn.cdrStore != null)
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _CdrDbDialog(conn: conn),
                    ),
                    icon: Icon(
                      conn.cdrConfigured
                          ? Icons.storage_rounded
                          : Icons.storage_outlined,
                      size: 16,
                    ),
                    label: Text(tr('Database CDR')),
                  ),
                TextButton.icon(
                  onPressed: () => phone.removeConnection(conn),
                  icon: Icon(Icons.delete_outline, size: 16, color: c.busyText),
                  label: Text(
                    tr('Rimuovi'),
                    style: TextStyle(color: c.busyText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cosa leggere dalle API e ogni quanto: una riga per voce di [PbxSync], con
/// le frequenze a radio button (e "Spenta" se la voce si può spegnere).
class _SyncSettings extends StatelessWidget {
  const _SyncSettings({required this.phone, required this.conn});
  final PhoneController phone;
  final PbxConnection conn;

  String _at(DateTime? t) {
    if (t == null) return tr('non ancora letta');
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('letta alle {t}', {'t': '${two(t.hour)}:${two(t.minute)}'});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final summary = [
      for (final s in PbxSync.values)
        '${s.label} ${syncEveryLabel(s.of(conn.syncSettings)).toLowerCase()}',
    ].join(' · ');
    return Theme(
      // Niente linee sopra e sotto l'ExpansionTile.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 40, bottom: 8),
        leading: Icon(Icons.tune_rounded, color: c.muted),
        title: Text(tr('Cosa sincronizzare e ogni quanto')),
        subtitle: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in PbxSync.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  Text(
                    '${s.help} · ${_at(conn.lastRead(s))}',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  RadioGroup<Duration>(
                    groupValue: s.of(conn.syncSettings),
                    onChanged: (d) {
                      if (d != null) phone.setSyncEvery(conn, s, d);
                    },
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final d in [
                          if (s.canDisable) Duration.zero,
                          ...s.choices,
                        ])
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => phone.setSyncEvery(conn, s, d),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Radio<Duration>(value: d),
                                  Text(
                                    syncEveryLabel(d),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Nuova connessione o sostituzione delle credenziali. Client ID e Secret sono
/// di sola scrittura: i campi partono sempre vuoti.
class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({required this.phone, this.conn});
  final PhoneController phone;
  final PbxConnection? conn;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.conn?.label ?? 'PBX');
  late final _baseUrl = TextEditingController(
    text: widget.conn?.baseUrl.isNotEmpty == true
        ? widget.conn!.baseUrl
        : 'https://${widget.phone.settings.account?.domain.split(':').first ?? ''}',
  );
  late final _ownExtension = TextEditingController(
    text: widget.conn?.ownExtension.isNotEmpty == true
        ? widget.conn!.ownExtension
        : widget.phone.settings.account?.username ?? '',
  );
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _label,
      _baseUrl,
      _ownExtension,
      _clientId,
      _clientSecret,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateUrl(String? v) {
    final u = Uri.tryParse(v?.trim() ?? '');
    if (u == null || u.host.isEmpty) return tr('URL non valido');
    if (u.scheme != 'https') return tr('Serve https://');
    return null;
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Obbligatorio') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final creds = ApiCredentials(
      baseUrl: _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
      clientId: _clientId.text.trim(),
      clientSecret: _clientSecret.text.trim(),
      ownExtension: _ownExtension.text.trim(),
    );
    final conn = widget.conn;
    try {
      if (conn == null) {
        await widget.phone.addConnection(_label.text.trim(), creds);
      } else {
        await widget.phone.updateConnection(
          conn,
          label: _label.text.trim(),
          creds: creds,
        );
      }
    } catch (e) {
      // Salvataggio locale non riuscito (es. cifratura): il pulsante torna
      // attivo e si dice cosa è successo, senza dettagli delle credenziali.
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('Credenziali non salvate: {e}', {'e': e.runtimeType}),
            ),
          ),
        );
      }
      return;
    }
    _clientId.clear();
    _clientSecret.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hint = widget.conn == null
        ? tr('Da Integrations > API sul PBX')
        : tr('Impostato · scrivi per sostituire');
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        widget.conn == null ? tr('Aggiungi PBX') : tr('Credenziali PBX'),
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _label,
                validator: _required,
                decoration: InputDecoration(labelText: tr('Nome')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrl,
                validator: _validateUrl,
                decoration: InputDecoration(
                  labelText: tr('Indirizzo API del PBX'),
                  hintText:
                      'https://pbx.esempio.it oppure https://10.0.0.5:8088',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownExtension,
                validator: _required,
                decoration: InputDecoration(
                  labelText: tr('Interno dell\'utente'),
                  helperText: tr(
                    'Il solo interno che l\'app legge e modifica con queste '
                    'credenziali; deve coincidere con l\'account SIP.',
                  ),
                  helperMaxLines: 2,
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
                tr(
                  'Accesso amministrativo al PBX: cifrate su questo PC per il '
                  'tuo utente Windows, mai mostrate né scritte nei log.',
                ),
                style: TextStyle(fontSize: 12, color: c.muted),
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
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? tr('Connessione…') : tr('Salva e connetti')),
        ),
      ],
    );
  }
}

/// Credenziali "Database Grant" del PBX per il CDR (Integrations > Database
/// Grant sul PBX). Sola scrittura come le credenziali API: le inserisce
/// l'amministratore, che decide anche se concedere il CDR di tutto il PBX.
class _CdrDbDialog extends StatefulWidget {
  const _CdrDbDialog({required this.conn});
  final PbxConnection conn;

  @override
  State<_CdrDbDialog> createState() => _CdrDbDialogState();
}

class _CdrDbDialogState extends State<_CdrDbDialog> {
  final _form = GlobalKey<FormState>();
  // Precompilato solo se è un indirizzo di rete locale: Database Grant va
  // usato in LAN/VPN (il certificato non viene verificato).
  late final _host = TextEditingController(
    text: _isLocal(widget.conn.host) ? widget.conn.host : '',
  );

  static bool _isLocal(String h) {
    final a = InternetAddress.tryParse(h);
    if (a == null || a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _secure = true;
  late bool _whole = widget.conn.cdrWholePbx;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in [_host, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Obbligatorio') : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await widget.conn.saveCdr(
        CdrDbCredentials(
          host: _host.text.trim(),
          user: _user.text.trim(),
          password: _password.text,
          secure: _secure,
          wholePbx: _whole,
        ),
      );
      _user.clear();
      _password.clear();
      // Prova: una pagina del CDR (del proprio interno, o di tutto il PBX).
      final rows = await widget.conn.readCdr(wholePbx: _whole);
      _ok = true;
      _result = tr('Collegato · {n} chiamate lette', {'n': rows.length});
    } catch (e) {
      _ok = false;
      // Solo il tipo d'errore: mai host, utente o password nei messaggi.
      _result = tr('Non collegato: {e}', {'e': e.runtimeType});
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hint = widget.conn.cdrConfigured
        ? tr('Impostato · scrivi per sostituire')
        : null;
    return AlertDialog(
      title: Text(tr('Database CDR')),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Dal PBX: Integrazioni > Database Grant. Aggiungi lì l’IP di '
                  'questo PC tra quelli consentiti.',
                ),
                style: DrinText.detail.copyWith(color: c.muted),
              ),
              const SizedBox(height: DrinSpace.s3),
              TextFormField(
                controller: _host,
                validator: _required,
                decoration: InputDecoration(
                  labelText: tr('Indirizzo del PBX'),
                  helperText: tr('Porta 3306 (fissa sul PBX)'),
                ),
              ),
              const SizedBox(height: DrinSpace.s3),
              TextFormField(
                controller: _user,
                validator: _required,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('Nome utente'),
                  hintText: hint,
                ),
              ),
              const SizedBox(height: DrinSpace.s3),
              TextFormField(
                controller: _password,
                validator: _required,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('Password'),
                  hintText: hint,
                ),
              ),
              const SizedBox(height: DrinSpace.s2),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _secure,
                onChanged: (v) => setState(() => _secure = v),
                title: Text(tr('Connessione cifrata (TLS)')),
                subtitle: Text(
                  _secure
                      ? tr(
                          'Il certificato del PBX non viene verificato: usare in rete '
                          'locale o VPN.',
                        )
                      : tr(
                          'Senza cifratura chi è sulla stessa rete vede le chiamate e '
                          'può ricavare la password del database.',
                        ),
                  style: _secure ? null : TextStyle(color: c.busyText),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _whole,
                onChanged: (v) => setState(() => _whole = v),
                title: Text(tr('Mostra il CDR di tutto il PBX')),
                subtitle: Text(
                  tr(
                    'Chi usa questo PC vede le chiamate di tutti gli interni. '
                    'Spento: solo quelle del proprio interno.',
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: DrinSpace.s2),
                Text(
                  _result!,
                  style: DrinText.body.copyWith(
                    color: _ok ? c.freeText : c.busyText,
                  ),
                ),
              ],
              const SizedBox(height: DrinSpace.s2),
              Text(
                tr(
                  'Accesso al database del PBX: cifrato su questo PC per il tuo '
                  'utente Windows, mai mostrato né scritto nei log.',
                ),
                style: DrinText.detail.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.conn.cdrConfigured)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await widget.conn.forgetCdr();
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: Text(tr('Rimuovi'), style: TextStyle(color: c.busyText)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_ok ? tr('Chiudi') : tr('Annulla')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? tr('Connessione…') : tr('Salva e prova')),
        ),
      ],
    );
  }
}
