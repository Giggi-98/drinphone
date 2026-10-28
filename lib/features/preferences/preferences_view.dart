import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/yeastar_api.dart';
import '../../core/sip/sip_engine.dart';
import '../account/api_dialog.dart';
import '../shell/widgets.dart';

/// Preferenze a schede (organizzazione ispirata a Linkus Desktop: Utente,
/// Presenza, Casella vocale, Audio, Funzionalità, Integrazione, Lingua…).
class PreferencesView extends StatelessWidget {
  const PreferencesView({super.key, required this.phone, this.initialTab = 0});
  final PhoneController phone;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final tabs = [
      (tr('Utente'), _UserTab(phone: phone)),
      if (phone.isYeastar) (tr('Presenza'), _PresenceTab(phone: phone)),
      (tr('Casella vocale'), _VoicemailTab(phone: phone)),
      (tr('Audio'), _AudioTab(phone: phone)),
      (tr('Funzionalità'), const _FeaturesTab()),
      if (phone.isYeastar)
        (tr('Integrazione PBX'), PbxConnectionsPanel(phone: phone)),
      (tr('Lingua'), _LanguageTab(phone: phone)),
      (tr('Diagnostica'), _DiagnosticsTab(phone: phone)),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialTab.clamp(0, tabs.length - 1),
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: c.accent,
              unselectedLabelColor: c.text,
              indicatorColor: c.accent,
              dividerColor: c.border,
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final t in tabs)
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: t.$2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riquadro con titolo, come le sezioni delle preferenze di Linkus.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          Divider(color: c.border, height: 1),
          Padding(padding: const EdgeInsets.all(18), child: child),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return SizedBox(
      width: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.field,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Utente

class _UserTab extends StatelessWidget {
  const _UserTab({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final a = phone.settings.account;
    final me = phone.primaryConnection?.directory
        .where((x) => x.number == a?.username)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: tr('Informazioni utente'),
          action: Tooltip(
            message: tr('Dati letti dal PBX: si modificano sul PBX'),
            child: Icon(Icons.lock_outline, size: 16, color: c.muted),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusAvatar(
                name: me?.name ?? a?.displayName ?? '?',
                presence: me?.presence ?? '',
                size: 64,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 14,
                  children: [
                    _Field(tr('Interno'), a?.username ?? ''),
                    _Field(tr('Nome'), me?.name ?? a?.displayName ?? ''),
                    _Field(tr('Email'), me?.email ?? ''),
                    _Field(tr('Cellulare'), me?.mobile ?? ''),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Card(
          title: tr('Account SIP'),
          action: TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AccountEditor(phone: phone),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('Aggiungi account')),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (phone.settings.accounts.isEmpty)
                Text(
                  tr('Nessun account SIP configurato.'),
                  style: TextStyle(color: c.muted),
                ),
              for (final x in phone.settings.accounts)
                _AccountTile(phone: phone, account: x),
              Text(
                tr(
                  'Il primo account è il principale. Ogni account chiama e '
                  'segue in BLF gli interni del PBX collegato.',
                ),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.phone, required this.account});
  final PhoneController phone;
  final SipAccount account;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final a = account;
    final (dot, state) = switch (phone.registrations[a.id]?.status) {
      RegistrationStatus.ok => (c.ok, tr('Registrato')),
      RegistrationStatus.progress => (c.ringing, tr('Registrazione…')),
      RegistrationStatus.failed => (c.busy, tr('Errore registrazione')),
      _ => (c.muted, tr('Non registrato')),
    };
    final pbx = phone.connectionOf(a)?.label;
    final primary = a.id == phone.settings.account?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.surface,
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
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AccountEditor(phone: phone, account: a),
            ),
            icon: Icon(Icons.edit_outlined, size: 18, color: c.muted),
          ),
          IconButton(
            tooltip: tr('Rimuovi account'),
            onPressed: () => phone.removeAccount(a.id),
            icon: Icon(Icons.delete_outline, size: 18, color: c.busyText),
          ),
        ],
      ),
    );
  }
}

/// Aggiunta o modifica di un account SIP, con il PBX a cui appartiene.
class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, required this.phone, this.account});
  final PhoneController phone;
  final SipAccount? account;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
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

// ----------------------------------------------------------------- Presenza

/// Presenza in profondità (stile Linkus): le sei presenze Yeastar, ognuna con
/// i suoi inoltri; squillo e opzioni. Dati da `extension/get`, sola lettura.
class _PresenceTab extends StatefulWidget {
  const _PresenceTab({required this.phone});
  final PhoneController phone;

  @override
  State<_PresenceTab> createState() => _PresenceTabState();
}

class _PresenceTabState extends State<_PresenceTab> {
  static const _statuses = [
    'available',
    'away',
    'business_trip',
    'do_not_disturb',
    'lunch',
    'off_work',
  ];

  /// Presenza di cui si guardano le impostazioni (null = quella attuale).
  String? _viewed;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await widget.phone.refreshOwnDetail();
    if (mounted) setState(() => _refreshing = false);
  }

  String _dest(PresenceForward f) {
    final dir = widget.phone.primaryConnection?.directory ?? const [];
    String ext() {
      final e = dir.where((x) => '${x.id}' == f.value).firstOrNull;
      return e == null ? f.value : '${e.number} ${e.name}';
    }

    return switch (f.dest) {
      'extension' => tr('Interno {n}', {'n': ext()}),
      'ext_vm' => tr('Casella vocale'),
      'mobile_number' => tr('Cellulare'),
      'external_num' => f.number,
      'ivr' => 'IVR',
      'queue' => tr('Coda'),
      'ring_group' => tr('Gruppo di squillo'),
      'call_flow' => 'Call flow',
      'group_vm' => tr('Casella vocale di gruppo'),
      'play_greeting' => tr('Messaggio registrato'),
      'end_call' => tr('Termina la chiamata'),
      'send_busy' => tr('Segnale di occupato'),
      _ => f.dest,
    };
  }

  Widget _forward(DrinColors c, String label, PresenceForward? f) {
    final on = f?.enabled ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _ReadOnlyCheck(on),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Text(label, style: TextStyle(color: c.text)),
          ),
          if (on)
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.arrow_forward_rounded, size: 14, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _dest(f!),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _forwards(
    DrinColors c,
    String title,
    String scope,
    PresenceSetting? s,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
      ),
      const SizedBox(height: 4),
      _forward(c, tr('Sempre'), s?.forwards['${scope}_always']),
      _forward(c, tr('Nessuna risposta'), s?.forwards['${scope}_no_answer']),
      _forward(c, tr('Occupato'), s?.forwards['${scope}_busy']),
    ],
  );

  Widget _option(DrinColors c, bool on, String label, [String extra = '']) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            _ReadOnlyCheck(on),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: c.text)),
            if (extra.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(extra, style: mono(c.muted, size: 12)),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final d = widget.phone.ownDetail;
    final current = d?.presence ?? widget.phone.ownPresence;
    final viewed = _viewed ?? (current.isEmpty ? 'available' : current);
    final setting = d?.settingOf(viewed);
    final note = Text(
      tr(
        'Sola lettura: presenze e inoltri si cambiano sul PBX o da Linkus. '
        'Cambiarli da qui richiede l’API in scrittura (extension/update), '
        'esclusa dalle decisioni di progetto.',
      ),
      style: TextStyle(fontSize: 12, color: c.muted),
    );
    if (widget.phone.primaryConnection == null) {
      return _Card(
        title: tr('Stato di presenza'),
        child: Text(
          tr('Non disponibile (collega il PBX)'),
          style: TextStyle(color: c.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: tr('Stato di presenza'),
          action: IconButton(
            tooltip: tr('Rileggi dal PBX'),
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final st in _statuses)
                    () {
                      final pr = presenceOf(c, st)!;
                      return ChoiceChip(
                        selected: st == viewed,
                        onSelected: (_) => setState(() => _viewed = st),
                        avatar: Icon(pr.$1, size: 16, color: pr.$2),
                        label: Text(
                          st == current ? '${pr.$3} · ${tr('attuale')}' : pr.$3,
                        ),
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 14),
              _Field(tr('Informazioni di presenza'), d?.customPresence ?? ''),
              if (d == null) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Dettaglio non ancora letto dal PBX.'),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
              const SizedBox(height: 12),
              note,
            ],
          ),
        ),
        _Card(
          title: tr('Inoltro di chiamata · {p}', {
            'p': presenceOf(c, viewed)!.$3,
          }),
          child: Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 380,
                child: _forwards(c, tr('Chiamate interne'), 'in', setting),
              ),
              SizedBox(
                width: 380,
                child: _forwards(c, tr('Chiamate esterne'), 'ex', setting),
              ),
            ],
          ),
        ),
        _Card(
          title: tr('Squillo e opzioni'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                tr('Timeout squillo (s)'),
                d?.ringTimeout == null ? '' : '${d!.ringTimeout}',
              ),
              const SizedBox(height: 10),
              _option(
                c,
                d?.ringMobile ?? false,
                tr('Squilla anche il cellulare'),
                d?.mobileNumber ?? '',
              ),
              _option(
                c,
                d?.acceptRingGroup ?? false,
                tr('Accetta chiamate dai gruppi di squillo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- Casella vocale

class _VoicemailTab extends StatefulWidget {
  const _VoicemailTab({required this.phone});
  final PhoneController phone;

  @override
  State<_VoicemailTab> createState() => _VoicemailTabState();
}

class _VoicemailTabState extends State<_VoicemailTab> {
  late final _code = TextEditingController(
    text: widget.phone.settings.voicemailCode,
  );

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _yes(bool v) => v ? tr('Sì') : tr('No');

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final d = widget.phone.ownDetail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_codeCard(c), if (d != null) _pbxCard(c, d)],
    );
  }

  /// Impostazioni della casella sul PBX (`extension/get`); il PIN non si
  /// legge né si mostra, solo se è richiesto.
  Widget _pbxCard(DrinColors c, PbxExtensionDetail d) => _Card(
    title: tr('Impostazioni sul PBX'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _Field(tr('Casella vocale attiva'), _yes(d.vmEnabled)),
            _Field(tr('PIN richiesto'), _yes(d.vmPinAuth)),
            _Field(tr('Notifica nuovi messaggi'), switch (d.vmNotification) {
              'no' => tr('Nessuna email'),
              'with_attach' => tr('Email con allegato'),
              'without_attach' => tr('Email senza allegato'),
              _ => d.vmNotification,
            }),
            _Field(tr('Dopo la notifica'), switch (d.vmAfterNotification) {
              'no' => tr('Lascia da ascoltare'),
              'mark_read' => tr('Segna come ascoltato'),
              'delete' => tr('Elimina'),
              _ => d.vmAfterNotification,
            }),
            _Field(tr('Annuncia data e ora'), _yes(d.vmPlayDatetime)),
            _Field(tr('Messaggio di benvenuto'), switch (d.vmGreeting) {
              'follow_system' => tr('Come il sistema'),
              'no_greeting' => tr('Nessuno'),
              _ => d.vmGreeting,
            }),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr('Sola lettura: si modificano sul PBX o da Linkus.'),
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    ),
  );

  Widget _codeCard(DrinColors c) {
    return _Card(
      title: tr('Casella vocale'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('{n} nuovi · {o} già ascoltati', {
              'n': widget.phone.voicemailNew,
              'o': widget.phone.voicemailOld,
            }),
            style: TextStyle(color: c.text),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 380,
            child: TextField(
              controller: _code,
              style: mono(c.text),
              decoration: InputDecoration(
                labelText: tr('Codice per ascoltare i messaggi'),
                helperText: tr('Yeastar P-Series: *2 (verifica sul tuo PBX)'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (_code.text.trim().isNotEmpty) {
                widget.phone.setVoicemailCode(_code.text);
              }
            },
            child: Text(tr('Salva')),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- Audio

class _AudioTab extends StatefulWidget {
  const _AudioTab({required this.phone});
  final PhoneController phone;

  @override
  State<_AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<_AudioTab> {
  late List<SoundDevice> _devices = widget.phone.soundDevices();

  Widget _picker(
    String label,
    IconData icon,
    bool Function(SoundDevice) fits,
    String current,
    void Function(String) onPick,
  ) {
    final list = _devices.where(fits).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: 520,
        child: DropdownButtonFormField<String>(
          initialValue: list.any((d) => d.id == current) ? current : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 18),
          ),
          items: [
            for (final d in list)
              DropdownMenuItem(
                value: d.id,
                child: Text(d.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onPick(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final (cap, play, ring) = widget.phone.audioDevices;
    final p = widget.phone;
    return _Card(
      title: tr('Dispositivi audio'),
      action: IconButton(
        tooltip: tr('Aggiorna elenco'),
        onPressed: () => setState(() => _devices = p.soundDevices()),
        icon: Icon(Icons.refresh_rounded, color: c.muted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _picker(
            tr('Microfono'),
            Icons.mic_none_rounded,
            (d) => d.capture,
            cap,
            (v) async {
              await p.setAudio(capture: v);
              setState(() {});
            },
          ),
          _picker(
            tr('Altoparlante / cuffia'),
            Icons.headphones_rounded,
            (d) => d.playback,
            play,
            (v) async {
              await p.setAudio(playback: v);
              setState(() {});
            },
          ),
          _picker(
            tr('Suoneria'),
            Icons.notifications_active_outlined,
            (d) => d.playback,
            ring,
            (v) async {
              await p.setAudio(ringer: v);
              setState(() {});
            },
          ),
          Text(
            tr(
              'Si applica subito e resta salvato. La suoneria può andare su un '
              'dispositivo diverso dalla cuffia (es. altoparlanti del PC).',
            ),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Funzionalità

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab();

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget row(IconData icon, String title, String why) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: c.muted),
      title: Text(title, style: TextStyle(color: c.text)),
      subtitle: Text(why, style: TextStyle(fontSize: 12, color: c.muted)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.keyBtn,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          tr('In preparazione'),
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
      ),
    );
    return _Card(
      title: tr('Funzionalità'),
      child: Column(
        children: [
          row(
            Icons.do_not_disturb_on_outlined,
            tr('Non disturbare'),
            tr('Stato sul PBX: richiede l’API in scrittura'),
          ),
          row(
            Icons.phone_forwarded_outlined,
            tr('Inoltro di chiamata'),
            tr('Regole di inoltro del PBX: richiede l’API in scrittura'),
          ),
          row(
            Icons.call_received_outlined,
            tr('Risposta automatica'),
            tr('Lato app: per interfono e citofoni'),
          ),
          row(
            Icons.rocket_launch_outlined,
            tr('Avvio con Windows'),
            tr('Lato app: con il pacchetto di installazione'),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- Lingua

class _LanguageTab extends StatelessWidget {
  const _LanguageTab({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) => _Card(
    title: tr('Lingua'),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<AppLang>(
        segments: [
          for (final l in AppLang.values)
            ButtonSegment(value: l, label: Text(l.label)),
        ],
        selected: {appLang.value},
        onSelectionChanged: (s) => phone.setLanguage(s.first),
      ),
    ),
  );
}

// --------------------------------------------------------------- Diagnostica

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return _Card(
      title: tr('Diagnostica'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Motore SIP: liblinphone {v}', {
              'v': phone.engineVersion.isEmpty ? '—' : phone.engineVersion,
            }),
            style: TextStyle(color: c.text),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: phone.settings.debugLog,
            onChanged: (v) => phone.setDebugLog(v ?? false),
            title: Text(tr('Log di debug del motore SIP')),
            subtitle: Text(
              tr('Attivo dal prossimo avvio. File in {d}', {'d': phone.logDir}),
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Process.run('explorer', [phone.logDir]),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(tr('Apri cartella log')),
          ),
        ],
      ),
    );
  }
}

/// Casella di sola lettura (valore letto dal PBX, non modificabile).
class _ReadOnlyCheck extends StatelessWidget {
  const _ReadOnlyCheck(this.on);
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return SizedBox(
      width: 20,
      height: 20,
      child: Checkbox(
        value: on,
        onChanged: null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        fillColor: WidgetStatePropertyAll(on ? c.accent : Colors.transparent),
        side: BorderSide(color: c.muted, width: 1.5),
      ),
    );
  }
}
