import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/yeastar_api.dart';
import '../../core/video/openh264.dart';
import '../../core/sip/sip_engine.dart';
import '../account/api_dialog.dart';
import '../call/native_video_view.dart';
import '../shell/widgets.dart';

/// Preferenze riorganizzate per ambito (Profilo vs Applicazione) con
/// transizioni fluide tra le sezioni e indicatori di stato visivi.
class PreferencesView extends StatefulWidget {
  const PreferencesView({super.key, required this.phone, this.initialTab = 0});
  final PhoneController phone;
  final int initialTab;

  @override
  State<PreferencesView> createState() => _PreferencesViewState();
}

class _PreferencesViewState extends State<PreferencesView> {
  late int _index = _mapInitialTab(widget.initialTab);

  int _mapInitialTab(int tab) {
    // 5 era "Integrazione PBX", ora unificata nella prima sezione con Account SIP.
    if (tab == 5 || tab == 0) return 0;
    if (tab == 1 && widget.phone.isYeastar) return 1;
    return tab;
  }

  @override
  void didUpdateWidget(covariant PreferencesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _index = _mapInitialTab(widget.initialTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final phone = widget.phone;
    final profileItems = <(IconData, String, Widget)>[
      (trIconAccount, tr('Account SIP'), _UserTab(phone: phone)),
      if (phone.isYeastar)
        (
          Icons.verified_user_outlined,
          tr('Presenza'),
          _PresenceTab(phone: phone),
        ),
      (
        Icons.voicemail_rounded,
        tr('Casella vocale'),
        _VoicemailTab(phone: phone),
      ),
    ];
    final appItems = <(IconData, String, Widget)>[
      (
        Icons.headphones_rounded,
        tr('Audio'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AudioSettings(phone: phone),
            _AdvancedTab(phone: phone),
            const _FeaturesTab(),
          ],
        ),
      ),
      (Icons.videocam_rounded, tr('Video'), _VideoTab(phone: phone)),
      (
        Icons.settings_suggest_rounded,
        tr('Diagnostica'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LanguageTab(phone: phone),
            _DiagnosticsTab(phone: phone),
          ],
        ),
      ),
    ];
    final all = [...profileItems, ...appItems];
    final idx = _index.clamp(0, all.length - 1);

    Widget navHeader(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: c.muted,
        ),
      ),
    );

    Widget navTile(int i, IconData icon, String label) {
      final active = i == idx;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _index = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? c.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? c.accent.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? c.accent : c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? c.accent : c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                navHeader(tr('Profilo')),
                for (var i = 0; i < profileItems.length; i++)
                  navTile(i, profileItems[i].$1, profileItems[i].$2),
                const SizedBox(height: 8),
                Divider(color: c.border, height: 1),
                navHeader(tr('Applicazione')),
                for (var i = 0; i < appItems.length; i++)
                  navTile(
                    profileItems.length + i,
                    appItems[i].$1,
                    appItems[i].$2,
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSectionSwitch(
              child: SingleChildScrollView(
                key: ValueKey('pref-scroll-$idx'),
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: all[idx].$3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const IconData trIconAccount = Icons.hub_rounded;
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
  const _Field(this.label, this.value, {this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.muted),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.text,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              StatusAvatar(
                name: me?.name ?? a?.displayName ?? '?',
                presence: me?.presence ?? '',
                size: 56,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _Field(
                      tr('Interno'),
                      a?.username ?? '',
                      icon: Icons.tag_rounded,
                    ),
                    _Field(
                      tr('Nome'),
                      me?.name ?? a?.displayName ?? '',
                      icon: Icons.person_outline_rounded,
                    ),
                    _Field(
                      tr('Email'),
                      me?.email ?? '',
                      icon: Icons.alternate_email_rounded,
                    ),
                    _Field(
                      tr('Cellulare'),
                      me?.mobile ?? '',
                      icon: Icons.smartphone_rounded,
                    ),
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
        if (phone.isYeastar) PbxConnectionsPanel(phone: phone),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [
                  if (phone.registrations[a.id]?.status ==
                      RegistrationStatus.ok)
                    BoxShadow(color: dot.withValues(alpha: 0.4), blurRadius: 6),
                ],
              ),
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

  // Avanzate.
  late final _proxy = TextEditingController(text: widget.account?.proxy);
  late final _registrar = TextEditingController(
    text: widget.account?.registrar,
  );
  late final _authUser = TextEditingController(text: widget.account?.authUser);
  late final _realm = TextEditingController(text: widget.account?.realm);
  late final _expires = TextEditingController(
    text: (widget.account?.expires ?? 0) > 0
        ? '${widget.account!.expires}'
        : '',
  );
  late final _vm = TextEditingController(text: widget.account?.voicemailCode);
  late final _stun = TextEditingController(text: widget.account?.stunServer);
  late final _turnUser = TextEditingController(text: widget.account?.turnUser);
  late final _turnPassword = TextEditingController(
    text: widget.account?.turnPassword,
  );
  late bool _register = widget.account?.registerEnabled ?? true;
  late bool _hideId = widget.account?.hideCallerId ?? false;
  late bool _ice = widget.account?.ice ?? false;
  late bool _turn = widget.account?.turn ?? false;
  late RecordingMode _recording =
      widget.account?.recording ?? RecordingMode.auto;
  late final _recordCode = TextEditingController(
    text: widget.account?.recordCode,
  );

  @override
  void dispose() {
    for (final c in [
      _name,
      _user,
      _password,
      _domain,
      _proxy,
      _registrar,
      _authUser,
      _realm,
      _expires,
      _vm,
      _stun,
      _turnUser,
      _turnPassword,
      _recordCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Obbligatorio') : null;

  String? _seconds(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 30 || n > 86400
        ? tr('Da 30 a 86400 secondi')
        : null;
  }

  Widget _group(DrinColors c, String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: c.muted,
      ),
    ),
  );

  Widget _field(TextEditingController t, String label, [String hint = '']) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: t,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint.isEmpty ? null : hint,
          ),
        ),
      );

  Widget _switch(
    String label,
    bool v,
    ValueChanged<bool> on, [
    String sub = '',
  ]) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: sub.isEmpty ? null : Text(sub),
    value: v,
    onChanged: on,
  );

  /// Voci tecniche, chiuse per default (come i softphone SIP classici).
  Widget _advanced(DrinColors c) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    shape: const Border(),
    collapsedShape: const Border(),
    initiallyExpanded:
        widget.account != null &&
        (widget.account!.proxy.isNotEmpty ||
            widget.account!.registrar.isNotEmpty ||
            widget.account!.authUser.isNotEmpty ||
            widget.account!.stunServer.isNotEmpty ||
            widget.account!.turn ||
            widget.account!.ice),
    title: Text(tr('Avanzate')),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _group(c, tr('SERVER')),
      _field(
        _proxy,
        tr('Proxy in uscita'),
        tr('sbc.esempio.it:5060 (vuoto = diretto)'),
      ),
      _field(
        _registrar,
        tr('Server registrar'),
        tr('vuoto = come il server SIP'),
      ),
      _field(
        _authUser,
        tr('Utente di autenticazione'),
        tr('vuoto = come l’utente'),
      ),
      _field(_realm, tr('Realm'), tr('vuoto = quello proposto dal server')),
      _group(c, tr('REGISTRAZIONE')),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _expires,
          validator: _seconds,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('Intervallo di registrazione (s)'),
            hintText: tr('vuoto = 3600'),
          ),
        ),
      ),
      _switch(
        tr('Registrazione attiva'),
        _register,
        (v) => setState(() => _register = v),
        tr('Spenta: l’account non si registra (solo chiamate in uscita)'),
      ),
      _group(c, tr('CHIAMATE')),
      _switch(
        tr('Nascondi ID chiamante'),
        _hideId,
        (v) => setState(() => _hideId = v),
        tr('Privacy: id, se PBX o trunk lo rispettano'),
      ),
      _field(
        _vm,
        tr('Codice casella vocale'),
        tr('vuoto = quello del profilo'),
      ),
      // Pulsante Registra della finestra di chiamata.
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<RecordingMode>(
          initialValue: _recording,
          decoration: InputDecoration(labelText: tr('Registrazione chiamate')),
          items: [
            DropdownMenuItem(
              value: RecordingMode.auto,
              child: Text(tr('Automatica · codice letto dalle API del PBX')),
            ),
            DropdownMenuItem(
              value: RecordingMode.pbxCode,
              child: Text(tr('Codice funzione del PBX')),
            ),
            DropdownMenuItem(
              value: RecordingMode.local,
              child: Text(tr('Locale sul PC (Documenti › DrinPhone)')),
            ),
            DropdownMenuItem(
              value: RecordingMode.off,
              child: Text(tr('Disattivata')),
            ),
          ],
          onChanged: (v) =>
              setState(() => _recording = v ?? RecordingMode.auto),
        ),
      ),
      if (_recording == RecordingMode.pbxCode)
        _field(_recordCode, tr('Codice di registrazione'), '*1'),
      if (_recording == RecordingMode.local)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            tr(
              'Registrare una conversazione richiede di norma il consenso '
              'dell’interlocutore.',
            ),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      _group(c, tr('RETE / NAT')),
      _field(_stun, tr('Server STUN/TURN'), tr('stun.esempio.it:3478')),
      _switch(
        tr('ICE'),
        _ice,
        (v) => setState(() => _ice = v),
        tr('Prova più percorsi per l’audio (con STUN/TURN)'),
      ),
      _switch(
        tr('TURN'),
        _turn,
        (v) => setState(() => _turn = v),
        tr('Audio tramite relay, per reti molto chiuse'),
      ),
      if (_turn) ...[
        _field(_turnUser, tr('Utente TURN')),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _turnPassword,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Password TURN')),
          ),
        ),
      ],
    ],
  );

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
        proxy: _proxy.text.trim(),
        registrar: _registrar.text.trim(),
        authUser: _authUser.text.trim(),
        realm: _realm.text.trim(),
        expires: int.tryParse(_expires.text.trim()) ?? 0,
        registerEnabled: _register,
        hideCallerId: _hideId,
        voicemailCode: _vm.text.trim(),
        stunServer: _stun.text.trim(),
        ice: _ice,
        turn: _turn,
        turnUser: _turn ? _turnUser.text.trim() : '',
        turnPassword: _turn ? _turnPassword.text : '',
        recording: _recording,
        recordCode: _recording == RecordingMode.pbxCode
            ? _recordCode.text.trim()
            : '',
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
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                // Profili SIP generici: nessuna connessione PBX da collegare.
                if (widget.phone.isYeastar) const SizedBox(height: 12),
                if (widget.phone.isYeastar)
                  DropdownButtonFormField<String>(
                    initialValue: conns.any((x) => x.id == _pbxId)
                        ? _pbxId
                        : '',
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
                const SizedBox(height: 8),
                _advanced(c),
              ],
            ),
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
            child: Text(label, style: TextStyle(color: on ? c.text : c.muted)),
          ),
          if (on)
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.arrow_forward_rounded, size: 14, color: c.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _dest(f!),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text('—', style: TextStyle(color: c.muted)),
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
                      final isCurrent = st == current;
                      return Tooltip(
                        message: isCurrent
                            ? '${pr.$3} · ${tr('attuale')}'
                            : pr.$3,
                        child: ChoiceChip(
                          selected: st == viewed,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _viewed = st),
                          avatar: Icon(pr.$1, size: 16, color: pr.$2),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(pr.$3),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: pr.$2,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 14),
              _Field(
                tr('Informazioni di presenza'),
                d?.customPresence ?? '',
                icon: Icons.chat_bubble_outline_rounded,
              ),
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
          child: AnimatedSectionSwitch(
            child: Wrap(
              key: ValueKey('fwd-wrap-$viewed'),
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
        ),
        _Card(
          title: tr('Squillo e opzioni'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                tr('Timeout squillo (s)'),
                d?.ringTimeout == null ? '' : '${d!.ringTimeout}',
                icon: Icons.timer_outlined,
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

  Widget _boolBadge(DrinColors c, String label, bool on) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReadOnlyCheck(on),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: c.text)),
      ],
    ),
  );

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
          spacing: 10,
          runSpacing: 10,
          children: [
            _boolBadge(c, tr('Casella vocale attiva'), d.vmEnabled),
            _boolBadge(c, tr('PIN richiesto'), d.vmPinAuth),
            _boolBadge(c, tr('Annuncia data e ora'), d.vmPlayDatetime),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _Field(tr('Notifica nuovi messaggi'), switch (d.vmNotification) {
              'no' => tr('Nessuna email'),
              'with_attach' => tr('Email con allegato'),
              'without_attach' => tr('Email senza allegato'),
              _ => d.vmNotification,
            }, icon: Icons.mark_email_unread_outlined),
            _Field(tr('Dopo la notifica'), switch (d.vmAfterNotification) {
              'no' => tr('Lascia da ascoltare'),
              'mark_read' => tr('Segna come ascoltato'),
              'delete' => tr('Elimina'),
              _ => d.vmAfterNotification,
            }, icon: Icons.done_all_rounded),
            _Field(tr('Messaggio di benvenuto'), switch (d.vmGreeting) {
              'follow_system' => tr('Come il sistema'),
              'no_greeting' => tr('Nessuno'),
              _ => d.vmGreeting,
            }, icon: Icons.record_voice_over_outlined),
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

/// Microfono, altoparlante e suoneria (anche nella procedura guidata).
class AudioSettings extends StatefulWidget {
  const AudioSettings({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<AudioSettings> createState() => _AudioSettingsState();
}

class _AudioSettingsState extends State<AudioSettings> {
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

/// Videochiamate: webcam, anteprima, codec (VP8 incluso; H264 da Cisco).
class _VideoTab extends StatefulWidget {
  const _VideoTab({required this.phone});
  final PhoneController phone;

  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> {
  bool _busy = false;

  PhoneController get p => widget.phone;

  bool _testing = false;

  void _set({
    bool? enabled,
    String? camera,
    bool? preview,
    VideoQuality? quality,
  }) {
    final o = p.settings.video;
    p.setVideoOptions(
      VideoOptions(
        enabled: enabled ?? o.enabled,
        camera: camera ?? o.camera,
        preview: preview ?? o.preview,
        quality: quality ?? o.quality,
      ),
    );
  }

  /// Consenso esplicito: il file arriva da Cisco, non da Econnet.
  Future<void> _install() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Scaricare il codec H264 da Cisco?')),
        content: SizedBox(
          width: 460,
          child: Text(
            tr(
              'DrinPhone scarica OpenH264 {v} dal sito ufficiale di Cisco '
              '(ciscobinary.openh264.org): così la licenza dei brevetti H264 è '
              'coperta da Cisco. Il file si accetta solo se la sua impronta '
              'coincide con quella verificata (firma Cisco, nessuna funzione di '
              'rete). Cisco riceve solo la richiesta di download (indirizzo IP '
              'e ora). Il codec funziona dopo il riavvio di DrinPhone.',
              {'v': OpenH264.version},
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Scarica')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    String msg;
    try {
      await p.installH264();
      msg = tr('H264 installato: riavvia DrinPhone per usarlo');
    } catch (e) {
      // Errore di rete o impronta diversa: niente viene installato.
      msg = tr('Download non riuscito: {e}', {'e': e.runtimeType});
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final o = p.settings.video;
    final cams = p.videoDevices();
    final codecs = p.videoCodecs();
    final h264 = codecs.contains('H264');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: tr('Videochiamate'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Videochiamate attive')),
                subtitle: Text(
                  tr(
                    'Pulsante videochiamata sugli interni e "Rispondi in video" '
                    'per le chiamate che offrono il video',
                  ),
                ),
                value: o.enabled,
                onChanged: (v) => _set(enabled: v),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 420,
                child: DropdownButtonFormField<String>(
                  initialValue: cams.contains(o.camera) ? o.camera : '',
                  decoration: InputDecoration(labelText: tr('Webcam')),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(tr('Predefinita di sistema')),
                    ),
                    for (final cam in cams)
                      DropdownMenuItem(
                        value: cam,
                        child: Text(cam, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: o.enabled ? (v) => _set(camera: v ?? '') : null,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 420,
                child: DropdownButtonFormField<VideoQuality>(
                  initialValue: o.quality,
                  decoration: InputDecoration(
                    labelText: tr('Qualità video inviata'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: VideoQuality.low,
                      child: Text(tr('Bassa · 480p (reti lente)')),
                    ),
                    DropdownMenuItem(
                      value: VideoQuality.medium,
                      child: Text(tr('Media · 720p')),
                    ),
                    DropdownMenuItem(
                      value: VideoQuality.high,
                      child: Text(tr('Alta · 1080p')),
                    ),
                  ],
                  onChanged: o.enabled ? (v) => _set(quality: v) : null,
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Anteprima della webcam')),
                subtitle: Text(
                  tr(
                    'Riquadro con la propria immagine durante la videochiamata',
                  ),
                ),
                value: o.preview,
                onChanged: o.enabled ? (v) => _set(preview: v) : null,
              ),
              const SizedBox(height: 8),
              // Prova fuori dalle chiamate: webcam e visualizzazione.
              OutlinedButton.icon(
                onPressed: o.enabled && p.calls.isEmpty
                    ? () => setState(() => _testing = !_testing)
                    : null,
                icon: Icon(
                  _testing
                      ? Icons.videocam_off_outlined
                      : Icons.videocam_outlined,
                ),
                label: Text(_testing ? tr('Ferma prova') : tr('Prova webcam')),
              ),
              if (_testing) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 480,
                  height: 270,
                  child: NativeVideoView(
                    label: tr('Video non disponibile su questa piattaforma'),
                    onHandle: p.setCameraTest,
                  ),
                ),
              ],
            ],
          ),
        ),
        _Card(
          title: tr('Codec video'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                codecs.isEmpty
                    ? tr('Nessun codec video disponibile')
                    : tr('In uso: {c}', {'c': codecs.join(', ')}),
                style: TextStyle(color: c.text),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    h264 ? Icons.check_circle_rounded : Icons.info_outline,
                    size: 18,
                    color: h264 ? c.ok : c.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h264
                          ? tr(
                              'H264: OpenH264 {v} di Cisco, impronta verificata',
                              {'v': OpenH264.version},
                            )
                          : p.h264NeedsRestart
                          ? tr('H264: installato, attivo dal prossimo avvio')
                          : tr(
                              'H264 non installato: molti videocitofoni e telefoni '
                              'SIP lo richiedono',
                            ),
                      style: TextStyle(color: c.text),
                    ),
                  ),
                  if (p.openH264 != null && !h264 && !p.h264NeedsRestart)
                    FilledButton.tonal(
                      onPressed: _busy ? null : _install,
                      child: Text(
                        _busy ? tr('Download…') : tr('Scarica da Cisco…'),
                      ),
                    ),
                  if (p.openH264 != null && (h264 || p.h264NeedsRestart))
                    TextButton(
                      onPressed: () async {
                        await p.removeH264();
                        if (mounted) setState(() {});
                      },
                      child: Text(tr('Rimuovi')),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  'VP8 è incluso e senza brevetti. H264 arriva da Cisco per '
                  'licenza: non è nel pacchetto di DrinPhone.',
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

/// Opzioni globali delle chiamate: in liblinphone 5.5 valgono per tutta l'app.
class _AdvancedTab extends StatelessWidget {
  const _AdvancedTab({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final o = phone.settings.callOptions;
    void set({
      MediaEncryption? encryption,
      bool? mandatory,
      bool? keepAlive,
      bool? dtmfInfo,
    }) => phone.setCallOptions(
      CallOptions(
        encryption: encryption ?? o.encryption,
        encryptionMandatory: mandatory ?? o.encryptionMandatory,
        keepAlive: keepAlive ?? o.keepAlive,
        dtmfInfo: dtmfInfo ?? o.dtmfInfo,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: tr('Cifratura audio'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 380,
                child: DropdownButtonFormField<MediaEncryption>(
                  initialValue: o.encryption,
                  decoration: InputDecoration(labelText: tr('Cifratura media')),
                  items: [
                    for (final e in MediaEncryption.values)
                      DropdownMenuItem(
                        value: e,
                        child: Text(switch (e) {
                          MediaEncryption.none => tr('Nessuna'),
                          MediaEncryption.srtp => 'SRTP (SDES)',
                          MediaEncryption.zrtp => 'ZRTP',
                          MediaEncryption.dtls => 'DTLS-SRTP',
                        }),
                      ),
                  ],
                  onChanged: (e) => set(encryption: e),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Obbligatoria')),
                subtitle: Text(
                  tr(
                    'Rifiuta le chiamate che il PBX non cifra allo stesso modo',
                  ),
                ),
                value: o.encryptionMandatory,
                onChanged: o.encryption == MediaEncryption.none
                    ? null
                    : (v) => set(mandatory: v),
              ),
              Text(
                tr(
                  'Vale per tutti gli account e per le nuove chiamate. SRTP '
                  'richiede di solito il trasporto TLS; se il PBX non usa la '
                  'stessa cifratura la chiamata cade o resta muta: provala.',
                ),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
        _Card(
          title: tr('Rete e toni'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Keep-alive')),
                subtitle: Text(
                  tr('Tiene aperto il NAT tra una registrazione e l’altra'),
                ),
                value: o.keepAlive,
                onChanged: (v) => set(keepAlive: v),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 380,
                child: DropdownButtonFormField<bool>(
                  initialValue: o.dtmfInfo,
                  decoration: InputDecoration(labelText: tr('Toni DTMF')),
                  items: [
                    DropdownMenuItem(
                      value: false,
                      child: Text(tr('RFC 2833 (nel flusso audio)')),
                    ),
                    DropdownMenuItem(value: true, child: Text(tr('SIP INFO'))),
                  ],
                  onChanged: (v) => set(dtmfInfo: v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguageTab extends StatelessWidget {
  const _LanguageTab({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: tr('Lingua'),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<AppLang>(
            segments: [
              for (final l in AppLang.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {appLang.value},
            onSelectionChanged: (s) => phone.setLanguage(s.first),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeMode,
            builder: (context, mode, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  tooltip: tr('Sistema'),
                  icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  tooltip: tr('Scuro'),
                  icon: const Icon(Icons.dark_mode_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  tooltip: tr('Chiaro'),
                  icon: const Icon(Icons.light_mode_rounded, size: 18),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => appThemeMode.value = s.first,
            ),
          ),
        ],
      ),
    );
  }
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

/// Indicatore visivo di sola lettura (valore booleano letto dal PBX): mostra
/// lo stato tramite icona e colore con etichetta nel tooltip.
class _ReadOnlyCheck extends StatelessWidget {
  const _ReadOnlyCheck(this.on);
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Tooltip(
      message: on ? tr('Sì') : tr('No'),
      child: Icon(
        on ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
        size: 18,
        color: on ? c.ok : c.muted,
      ),
    );
  }
}
