import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/yeastar_api.dart';
import '../../core/platform/audio_player.dart';
import '../../core/platform/autostart.dart';
import '../../core/platform/screen_pop.dart';
import '../../core/video/openh264.dart';
import '../../core/sip/sip_engine.dart';
import '../account/api_dialog.dart';
import '../call/native_video_view.dart';
import '../setup/profile_bundle_dialog.dart';
import '../shell/widgets.dart';
import '../update/update_panel.dart';

part 'own_extension.dart';

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

  /// Barra "Salva / Annulla" della sezione aperta, fissa in basso.
  final _bar = ValueNotifier<Widget?>(null);

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

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
        tr('Audio & Suonerie'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AudioSettings(phone: phone),
            _RingtoneAndGainCard(phone: phone),
            _AudioCodecsCard(phone: phone),
            if (phone.recordingsDir.isNotEmpty)
              _LocalRecordingsCard(phone: phone),
          ],
        ),
      ),
      (
        Icons.bolt_rounded,
        tr('Chiamate & Automazioni'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AutoAnswerCard(phone: phone),
            _FeaturesTab(phone: phone),
          ],
        ),
      ),
      (
        Icons.shield_outlined,
        tr('Rete & Sicurezza'),
        _NetworkSecurityCards(phone: phone),
      ),
      (Icons.videocam_rounded, tr('Video'), _VideoTab(phone: phone)),
      (
        Icons.settings_suggest_rounded,
        tr('Diagnostica'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UiZoomCard(phone: phone),
            _DiagnosticsTab(phone: phone),
            if (phone.updater case final u?)
              _Card(
                title: tr('Aggiornamenti'),
                child: UpdatePanel(phone: phone, updater: u),
              ),
          ],
        ),
      ),
    ];
    final all = [...profileItems, ...appItems];
    final idx = _index.clamp(0, all.length - 1);

    Widget navHeader(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(label, style: DrinText.label.copyWith(color: c.muted)),
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
            child: _BarSlot(
              bar: _bar,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AnimatedSectionSwitch(
                      child: SingleChildScrollView(
                        key: ValueKey('pref-scroll-$idx'),
                        padding: const EdgeInsets.all(20),
                        child: all[idx].$3,
                      ),
                    ),
                  ),
                  // Modifiche in sospeso: la barra resta visibile mentre si
                  // scorre, e compare/scompare in `base`.
                  ValueListenableBuilder<Widget?>(
                    valueListenable: _bar,
                    builder: (context, bar, _) => AnimatedSize(
                      duration: DrinMotion.of(context, DrinMotion.base),
                      curve: DrinMotion.curve,
                      child: bar == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                              child: bar,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const IconData trIconAccount = Icons.hub_rounded;
}

/// Posto della barra "Salva / Annulla" in fondo alle Preferenze: la sezione
/// aperta ci mette la sua (vedi `_OwnExtensionDraft.saveBar`).
class _BarSlot extends InheritedWidget {
  const _BarSlot({required this.bar, required super.child});
  final ValueNotifier<Widget?> bar;

  static ValueNotifier<Widget?>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_BarSlot>()?.bar;

  @override
  bool updateShouldNotify(_BarSlot old) => bar != old.bar;
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
          Padding(
            padding: const EdgeInsets.all(18),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ],
      ),
    );
  }
}


/// Campi su griglia a 2 colonne (1 sotto i 640 px, misurati dopo scala e
/// zoom): stessa larghezza e altezza per tutti, come le sezioni ordinate dei
/// pannelli PBX (PIANO-AZIONE, blocco H).
class _FieldGrid extends StatelessWidget {
  const _FieldGrid(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth >= 640 ? 2 : 1;
      const gap = DrinSpace.s4;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: DrinSpace.s3,
        children: [for (final f in children) SizedBox(width: w, child: f)],
      );
    },
  );
}

/// Valore sì/no come simbolo: ✓ `freeText` o ✕ `muted`, con la parola accanto.
Widget _yesNo(BuildContext context, bool on) {
  final c = context.drin;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        on ? Icons.check_circle_rounded : Icons.cancel_outlined,
        size: 16,
        color: on ? c.freeText : c.muted,
      ),
      const SizedBox(width: DrinSpace.s1),
      Text(
        on ? tr('Sì') : tr('No'),
        style: DrinText.heading.copyWith(color: c.ink),
      ),
    ],
  );
}

/// Elenco breve come chip `panel` (es. trasporti "UDP" "TCP" "TLS").
Widget _chips(BuildContext context, List<String> items) {
  final c = context.drin;
  return Wrap(
    spacing: DrinSpace.s1,
    runSpacing: DrinSpace.s1,
    children: [
      for (final t in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: DrinSpace.s2),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(DrinRadius.pill),
          ),
          child: Text(t, style: DrinText.label.copyWith(color: c.ink)),
        ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.icon, this.content});
  final String label;
  final String value;
  final IconData? icon;

  /// Valore disegnato (simbolo, chip) al posto del testo [value].
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Container(
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
                content ??
                    // Valore troncato (es. email lunga): intero nel tooltip.
                    Tooltip(
                      message: value,
                      child: Text(
                        value.isEmpty ? '—' : value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
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
                child: _FieldGrid([
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
                ]),
              ),
            ],
          ),
        ),
        _Card(
          title: tr('Account SIP'),
          action: a != null
              ? null
              : TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AccountEditor(phone: phone),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('Configura')),
                ),
          child: a == null
              ? Text(
                  tr('Nessun account SIP configurato.'),
                  style: TextStyle(color: c.muted),
                )
              : _AccountTile(phone: phone, account: a),
        ),
        if (phone.isYeastar) PbxConnectionsPanel(phone: phone),
        _Card(
          title: tr('Trasferimento e backup profilo'),
          child: Wrap(
            spacing: DrinSpace.s3,
            runSpacing: DrinSpace.s2,
            children: [
              OutlinedButton.icon(
                onPressed: () => showExportProfileDialog(context, phone),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(tr('Esporta profilo (.drinprof)')),
              ),
              OutlinedButton.icon(
                onPressed: () => showImportProfileDialog(context, phone),
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: Text(tr('Importa profilo (.drinprof)')),
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
      RegistrationStatus.progress => (c.away, tr('Registrazione…')),
      RegistrationStatus.failed => (c.busy, tr('Errore registrazione')),
      _ => (c.muted, tr('Non registrato')),
    };
    final pbx = phone.connectionOf(a)?.label;
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
                        nameIsNumber(a.displayName, a.username)
                            ? a.username
                            : '${a.displayName} · ${a.username}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  [
                    '${a.domain} · ${a.transport.name.toUpperCase()}',
                    // "PBX: PBX" con l'etichetta predefinita non dice nulla.
                    if (pbx != null && pbx.trim().toUpperCase() != 'PBX')
                      'PBX: $pbx',
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
  late final String _pbxId = widget.account?.pbxId ?? '';

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
    child: Text(title, style: DrinText.label.copyWith(color: c.muted)),
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
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(tr('Account SIP')),
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

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _codeCard(c),
        if (widget.phone.ownDetail != null)
          _VoicemailPbxCard(phone: widget.phone),
      ],
    );
  }

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
  late int _rev = widget.phone.audioDeviceRevision;

  @override
  void initState() {
    super.initState();
    widget.phone.addListener(_onPhone);
  }

  @override
  void didUpdateWidget(covariant AudioSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phone != widget.phone) {
      oldWidget.phone.removeListener(_onPhone);
      widget.phone.addListener(_onPhone);
      _rev = widget.phone.audioDeviceRevision;
      _devices = widget.phone.soundDevices();
    }
  }

  @override
  void dispose() {
    widget.phone.removeListener(_onPhone);
    super.dispose();
  }

  void _onPhone() {
    if (_rev != widget.phone.audioDeviceRevision && mounted) {
      _rev = widget.phone.audioDeviceRevision;
      setState(() => _devices = widget.phone.soundDevices());
    }
  }

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
          const SizedBox(height: DrinSpace.s4),
          ListenableBuilder(
            listenable: p.echoTester,
            builder: (_, _) {
              final echo = p.echoTester;
              final busy = echo.phase != EchoTestPhase.idle;
              final status = switch (echo.phase) {
                EchoTestPhase.idle => tr(
                  'Registra fino a 5 secondi dal microfono e riascolta subito in cuffia.',
                ),
                EchoTestPhase.recording => tr(
                  'Parla ora nel microfono… ({s} s)',
                  {'s': echo.secondsLeft},
                ),
                EchoTestPhase.playing => tr('Riproduzione test microfono in corso…'),
              };
              return Container(
                padding: const EdgeInsets.all(DrinSpace.s3),
                decoration: BoxDecoration(
                  color: c.raised,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(DrinRadius.row),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          echo.phase == EchoTestPhase.recording
                              ? Icons.mic_rounded
                              : echo.phase == EchoTestPhase.playing
                              ? Icons.volume_up_rounded
                              : Icons.graphic_eq_rounded,
                          size: 18,
                          color: busy ? c.primary : c.muted,
                        ),
                        const SizedBox(width: DrinSpace.s2),
                        Expanded(
                          child: Text(
                            status,
                            style: DrinText.body.copyWith(color: c.ink),
                          ),
                        ),
                        if (!busy)
                          OutlinedButton.icon(
                            onPressed: echo.start,
                            icon: const Icon(Icons.mic_none_rounded, size: 17),
                            label: Text(tr('Prova audio (Echo Test)')),
                          )
                        else ...[
                          if (echo.phase == EchoTestPhase.recording) ...[
                            FilledButton(
                              onPressed: echo.finishRecordingAndPlay,
                              child: Text(tr('Riascolta ora')),
                            ),
                            const SizedBox(width: DrinSpace.s2),
                          ],
                          OutlinedButton(
                            onPressed: echo.stop,
                            child: Text(tr('Ferma')),
                          ),
                        ],
                      ],
                    ),
                    if (echo.error != null) ...[
                      const SizedBox(height: DrinSpace.s1),
                      Text(
                        echo.error!,
                        style: DrinText.detail.copyWith(color: c.busyText),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RingtoneAndGainCard extends StatelessWidget {
  const _RingtoneAndGainCard({required this.phone});
  final PhoneController phone;

  Future<void> _pickCustom(BuildContext context) async {
    final f = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'Audio WAV', extensions: const ['wav']),
      ],
    );
    if (f == null) return;
    await phone.setRingtone(f.path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final rings = phone.builtInRingtones();
    final cur = phone.settings.ringtone;
    final isCustom = cur.isNotEmpty && !rings.any((r) => r.$1 == cur);
    return _Card(
      title: tr('Suonerie e guadagno audio'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DrinSpace.s2,
            runSpacing: DrinSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: DropdownButtonFormField<String>(
                  initialValue: cur.isEmpty || rings.any((r) => r.$1 == cur) || isCustom
                      ? cur
                      : '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Suoneria chiamata entrante'),
                    prefixIcon: const Icon(Icons.music_note_outlined, size: 18),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(tr('Predefinita (telefono classico)')),
                    ),
                    for (final (path, label) in rings)
                      DropdownMenuItem(
                        value: path,
                        child: Text(tr(label), overflow: TextOverflow.ellipsis),
                      ),
                    if (isCustom)
                      DropdownMenuItem(
                        value: cur,
                        child: Text(
                          cur.split(Platform.pathSeparator).last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) phone.setRingtone(v);
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickCustom(context),
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: Text(tr('Sfoglia .wav…')),
              ),
              FilledButton.tonalIcon(
                onPressed: phone.previewRingtone,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(tr('Prova suoneria')),
              ),
              OutlinedButton(
                onPressed: phone.stopRingtonePreview,
                child: Text(tr('Ferma')),
              ),
            ],
          ),
          const SizedBox(height: DrinSpace.s4),
          Row(
            children: [
              SizedBox(
                width: 190,
                child: Text(
                  tr('Guadagno microfono'),
                  style: DrinText.body.copyWith(color: c.ink),
                ),
              ),
              Expanded(
                child: Slider(
                  value: phone.settings.micGainDb.clamp(-10.0, 15.0),
                  min: -10,
                  max: 15,
                  divisions: 25,
                  label: '${phone.settings.micGainDb.toStringAsFixed(0)} dB',
                  onChanged: (v) => phone.setAudioGains(micDb: v),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  '${phone.settings.micGainDb >= 0 ? '+' : ''}${phone.settings.micGainDb.toStringAsFixed(0)} dB',
                  textAlign: TextAlign.end,
                  style: DrinText.number.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 190,
                child: Text(
                  tr('Volume ascolto (dB)'),
                  style: DrinText.body.copyWith(color: c.ink),
                ),
              ),
              Expanded(
                child: Slider(
                  value: phone.settings.playbackGainDb.clamp(-10.0, 15.0),
                  min: -10,
                  max: 15,
                  divisions: 25,
                  label: '${phone.settings.playbackGainDb.toStringAsFixed(0)} dB',
                  onChanged: (v) => phone.setAudioGains(playbackDb: v),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  '${phone.settings.playbackGainDb >= 0 ? '+' : ''}${phone.settings.playbackGainDb.toStringAsFixed(0)} dB',
                  textAlign: TextAlign.end,
                  style: DrinText.number.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Tono discreto in cuffia su seconda chiamata')),
            subtitle: Text(
              tr(
                'Riproduce un breve avviso acustico in cuffia quando arriva una chiamata mentre sei già al telefono.',
              ),
            ),
            value: phone.settings.callWaitingTone,
            onChanged: phone.setCallWaitingTone,
          ),
        ],
      ),
    );
  }
}

class _LocalRecordingsCard extends StatefulWidget {
  const _LocalRecordingsCard({required this.phone});
  final PhoneController phone;

  @override
  State<_LocalRecordingsCard> createState() => _LocalRecordingsCardState();
}

class _LocalRecordingsCardState extends State<_LocalRecordingsCard> {
  late Future<List<File>> _files = widget.phone.listLocalRecordings();

  void _refresh() =>
      setState(() => _files = widget.phone.listLocalRecordings());

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    return _Card(
      title: tr('Registrazioni locali'),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Platform.isWindows)
            TextButton.icon(
              onPressed: () {
                Directory(p.recordingsDir).createSync(recursive: true);
                Process.start('explorer.exe', [p.recordingsDir]);
              },
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: Text(tr('Apri cartella')),
            ),
          IconButton(
            tooltip: tr('Aggiorna elenco'),
            onPressed: _refresh,
            icon: Icon(Icons.refresh_rounded, color: c.muted),
          ),
        ],
      ),
      child: FutureBuilder<List<File>>(
        future: _files,
        builder: (_, snap) {
          final items = (snap.data ?? const <File>[]).take(10).toList();
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const SizedBox(height: 24);
          }
          if (items.isEmpty) {
            return Text(
              tr('Nessuna registrazione locale salvata in {d}.', {
                'd': p.recordingsDir,
              }),
              style: DrinText.body.copyWith(color: c.muted),
            );
          }
          return ListenableBuilder(
            listenable: p.mediaPlayer,
            builder: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in items)
                  Builder(
                    builder: (_) {
                      final name = f.path.split(Platform.pathSeparator).last;
                      final lower = name.toLowerCase();
                      final playable =
                          lower.endsWith('.wav') || lower.endsWith('.mp3');
                      final key = 'localrec:${f.path}';
                      final playing =
                          p.mediaPlayer.isActive(key) && p.mediaPlayer.isPlaying;
                      final stat = f.statSync();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: DrinSpace.s2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.audio_file_outlined,
                              size: 18,
                              color: c.muted,
                            ),
                            const SizedBox(width: DrinSpace.s2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: DrinText.body.copyWith(color: c.ink),
                                  ),
                                  Text(
                                    _size(stat.size),
                                    style: DrinText.detail.copyWith(
                                      color: c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (playable)
                              OutlinedButton.icon(
                                onPressed: () => p.mediaPlayer.togglePlay(
                                  key,
                                  () async => f,
                                  cacheFile: false,
                                ),
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  playing ? tr('Pausa') : tr('Riproduci'),
                                ),
                              )
                            else if (Platform.isWindows)
                              OutlinedButton.icon(
                                onPressed: () => Process.start(
                                  'explorer.exe',
                                  ['/select,', f.path],
                                ),
                                icon: const Icon(
                                  Icons.folder_open_outlined,
                                  size: 16,
                                ),
                                label: Text(tr('Mostra file')),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AudioCodecsCard extends StatefulWidget {
  const _AudioCodecsCard({required this.phone});
  final PhoneController phone;

  @override
  State<_AudioCodecsCard> createState() => _AudioCodecsCardState();
}

class _AudioCodecsCardState extends State<_AudioCodecsCard> {
  Future<void> _apply(List<AudioCodecInfo> list) async {
    await widget.phone.setAudioCodecs([
      for (final c in list) AudioCodecPref(c.id, enabled: c.enabled),
    ]);
    if (mounted) setState(() {});
  }

  void _move(List<AudioCodecInfo> list, int i, int delta) {
    final target = i + delta;
    if (target < 0 || target >= list.length) return;
    final copy = [...list];
    final item = copy.removeAt(i);
    copy.insert(target, item);
    _apply(copy);
  }

  void _toggle(List<AudioCodecInfo> list, int i, bool value) {
    if (!value && list.where((x) => x.enabled).length <= 1) return;
    final cur = list[i];
    final copy = [...list];
    copy[i] = AudioCodecInfo(
      id: cur.id,
      mime: cur.mime,
      clockRate: cur.clockRate,
      channels: cur.channels,
      enabled: value,
    );
    _apply(copy);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final codecs = widget.phone.audioCodecs();
    return _Card(
      title: tr('Codec audio'),
      child: codecs.isEmpty
          ? Text(
              tr('Nessun codec audio disponibile dal motore.'),
              style: TextStyle(fontSize: 13, color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < codecs.length; i++)
                  () {
                    final x = codecs[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${x.mime} · ${x.clockRate} Hz'
                              '${x.channels > 1 ? ' · ${x.channels} ch' : ''}',
                              style: DrinText.body.copyWith(
                                color: x.enabled ? c.ink : c.muted,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Sposta su'),
                            onPressed: i == 0
                                ? null
                                : () => _move(codecs, i, -1),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 16,
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Sposta giù'),
                            onPressed: i == codecs.length - 1
                                ? null
                                : () => _move(codecs, i, 1),
                            icon: const Icon(
                              Icons.arrow_downward_rounded,
                              size: 16,
                            ),
                          ),
                          Switch(
                            value: x.enabled,
                            onChanged: (v) => _toggle(codecs, i, v),
                          ),
                        ],
                      ),
                    );
                  }(),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Ordine di preferenza nella negoziazione SIP (dall’alto al basso).',
                  ),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
    );
  }
}


// ------------------------------------------------------------ Funzionalità

class _FeaturesTab extends StatefulWidget {
  const _FeaturesTab({required this.phone});
  final PhoneController phone;

  @override
  State<_FeaturesTab> createState() => _FeaturesTabState();
}

class _FeaturesTabState extends State<_FeaturesTab> {
  // Letto dal registro di Windows (HKCU...Run), la fonte vera.
  bool _autostart = Autostart.enabled;
  late final _crmUrl = TextEditingController(
    text: widget.phone.settings.crmUrlTemplate,
  );
  bool _crmDirty = false;
  bool _crmInvalid = false;

  @override
  void didUpdateWidget(covariant _FeaturesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_crmDirty && _crmUrl.text != widget.phone.settings.crmUrlTemplate) {
      _crmUrl.text = widget.phone.settings.crmUrlTemplate;
    }
  }

  @override
  void dispose() {
    _crmUrl.dispose();
    super.dispose();
  }

  Future<void> _saveCrm({bool? autoOpen}) async {
    final tpl = _crmUrl.text.trim();
    if (tpl.isNotEmpty &&
        buildScreenPopUri(tpl, number: '100', name: 'Test') == null) {
      setState(() => _crmInvalid = true);
      return;
    }
    setState(() {
      _crmInvalid = false;
      _crmDirty = false;
    });
    await widget.phone.setCrmPreferences(
      urlTemplate: tpl,
      autoOpen: autoOpen ?? widget.phone.settings.crmAutoOpen,
    );
  }

  static String _fmtMin(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pickMinute({required bool isFrom}) async {
    final cur = isFrom
        ? widget.phone.settings.autoDndFromMinute
        : widget.phone.settings.autoDndToMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null || !mounted) return;
    final mins = picked.hour * 60 + picked.minute;
    await widget.phone.setAutoDndPreferences(
      fromMinute: isFrom ? mins : null,
      toMinute: isFrom ? null : mins,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    return _Card(
      title: tr('Funzionalità'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isWindows) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.rocket_launch_outlined, color: c.muted),
              title: Text(tr('Avvio con Windows')),
              subtitle: Text(
                tr('Parte all’accesso a Windows, nella barra di sistema.'),
              ),
              value: _autostart,
              onChanged: (v) {
                Autostart.set(v);
                setState(() => _autostart = Autostart.enabled);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.minimize_rounded, color: c.muted),
              title: Text(tr('Resta nella barra di sistema')),
              subtitle: Text(
                tr(
                  'Chiudendo la finestra le chiamate continuano ad arrivare; '
                  'per uscire: Esci dall’icona vicino all’orologio.',
                ),
              ),
              value: p.settings.closeToTray,
              onChanged: (v) async {
                await p.setCloseToTray(v);
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.keyboard_command_key_rounded, color: c.muted),
              title: Text(tr('Scorciatoie globali (Windows)')),
              subtitle: Text(
                tr(
                  'Ctrl+Alt+A rispondi/termina · Ctrl+Alt+M muto · '
                  'Ctrl+Alt+D chiama numero negli appunti (anche ridotto a icona).',
                ),
              ),
              value: p.settings.globalHotkeys,
              onChanged: (v) async {
                await p.setGlobalHotkeys(v);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.link_rounded, color: c.muted),
              title: Text(tr('Link telefonici (tel:, sip:)')),
              subtitle: Text(
                tr(
                  'Per chiamare dai link di browser e Outlook, scegliete '
                  'DrinPhone nelle app predefinite di Windows. Prima di '
                  'chiamare DrinPhone chiede sempre conferma.',
                ),
              ),
              trailing: OutlinedButton(
                // URI fisso; registeredAppUser = RegisteredApplications
                // scritto dall'installatore.
                onPressed: () => Process.start('explorer.exe', [
                  'ms-settings:defaultapps?registeredAppUser=DrinPhone',
                ]),
                child: Text(tr('App predefinite')),
              ),
            ),
            const Divider(height: DrinSpace.s5),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_browser_rounded, color: c.muted),
            title: Text(tr('Screen Pop CRM / Gestionale')),
            subtitle: Text(
              tr(
                'Apri un URL HTTP/HTTPS con {number} e {name} alla risposta o all’arrivo chiamata.',
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _crmUrl,
                  onChanged: (_) => setState(() {
                    _crmDirty = true;
                    _crmInvalid = false;
                  }),
                  decoration: InputDecoration(
                    hintText: 'https://crm.esempio.it/cerca?tel={number}',
                    errorText: _crmInvalid
                        ? tr('Inserisci un URL http:// o https:// valido')
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: DrinSpace.s3),
              FilledButton(
                onPressed: _crmDirty || _crmUrl.text.trim() != p.settings.crmUrlTemplate
                    ? () => _saveCrm()
                    : null,
                child: Text(tr('Salva')),
              ),
            ],
          ),
          const SizedBox(height: DrinSpace.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Apri CRM automaticamente all’arrivo chiamata')),
            subtitle: Text(
              tr(
                'Se disattivo, compare comunque il pulsante «Apri CRM» nella finestra di chiamata.',
              ),
            ),
            value: p.settings.crmAutoOpen,
            onChanged: (v) => _saveCrm(autoOpen: v),
          ),
          const Divider(height: DrinSpace.s5),
          if (Platform.isWindows)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.mic_off_outlined, color: c.muted),
              title: Text(tr('Auto-DND durante altre call (Teams, Meet, Zoom…)')),
              subtitle: Text(
                tr(
                  'Passa automaticamente in «Non disturbare» sul PBX quando un’altra app usa il microfono e ripristina lo stato alla fine.',
                ),
              ),
              value: p.settings.autoDndOnExternalMic,
              onChanged: (v) => p.setAutoDndPreferences(onExternalMic: v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.bedtime_outlined, color: c.muted),
            title: Text(tr('Auto-DND per fascia oraria')),
            subtitle: Text(
              tr(
                'Attiva automaticamente «Non disturbare» fuori orario o in pausa e ripristina allo scadere.',
              ),
            ),
            value: p.settings.autoDndScheduleEnabled,
            onChanged: (v) => p.setAutoDndPreferences(scheduleEnabled: v),
          ),
          if (p.settings.autoDndScheduleEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: DrinSpace.s2),
              child: Wrap(
                spacing: DrinSpace.s3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(tr('Dalle'), style: DrinText.body.copyWith(color: c.muted)),
                  OutlinedButton(
                    onPressed: () => _pickMinute(isFrom: true),
                    child: Text(_fmtMin(p.settings.autoDndFromMinute)),
                  ),
                  Text(tr('alle'), style: DrinText.body.copyWith(color: c.muted)),
                  OutlinedButton(
                    onPressed: () => _pickMinute(isFrom: false),
                    child: Text(_fmtMin(p.settings.autoDndToMinute)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// Videochiamate: webcam, anteprima, codec (VP8 incluso; H264 da Cisco).
class _VideoTab extends StatefulWidget {
  const _VideoTab({required this.phone});
  final PhoneController phone;

  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> {
  bool _busy = false;

  @override
  void dispose() {
    if (_testing) p.setCameraTest(false);
    super.dispose();
  }

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
                    ? () {
                        setState(() => _testing = !_testing);
                        p.setCameraTest(_testing);
                      }
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
                  child: VideoSlot(
                    surface: p.previewSurface,
                    label: tr('Video non disponibile su questa piattaforma'),
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

/// Opzioni globali di rete e sicurezza chiamate (SRTP/ZRTP/DTLS, Keep-alive, DTMF).
class _NetworkSecurityCards extends StatelessWidget {
  const _NetworkSecurityCards({required this.phone});
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
        autoAnswer: o.autoAnswer,
        autoAnswerDelaySeconds: o.autoAnswerDelaySeconds,
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
                  isExpanded: true,
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
                style: DrinText.detail.copyWith(color: c.muted),
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
                  isExpanded: true,
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

class _AutoAnswerCard extends StatelessWidget {
  const _AutoAnswerCard({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final o = phone.settings.callOptions;
    void set({bool? autoAnswer, int? autoAnswerDelaySeconds}) =>
        phone.setCallOptions(
          CallOptions(
            encryption: o.encryption,
            encryptionMandatory: o.encryptionMandatory,
            keepAlive: o.keepAlive,
            dtmfInfo: o.dtmfInfo,
            autoAnswer: autoAnswer ?? o.autoAnswer,
            autoAnswerDelaySeconds:
                autoAnswerDelaySeconds ?? o.autoAnswerDelaySeconds,
          ),
        );
    return _Card(
      title: tr('Risposta automatica'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Rispondi automaticamente alle chiamate')),
            subtitle: Text(
              tr(
                'Risponde da sola alle chiamate entranti se non hai già '
                'un’altra conversazione attiva.',
              ),
            ),
            value: o.autoAnswer,
            onChanged: (v) => set(autoAnswer: v),
          ),
          if (o.autoAnswer) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 380,
              child: DropdownButtonFormField<int>(
                initialValue: const [0, 2, 3, 5].contains(
                  o.autoAnswerDelaySeconds,
                )
                    ? o.autoAnswerDelaySeconds
                    : 0,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Ritardo prima di rispondere'),
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text(tr('Subito (0 s)'))),
                  DropdownMenuItem(value: 2, child: Text(tr('2 secondi'))),
                  DropdownMenuItem(value: 3, child: Text(tr('3 secondi'))),
                  DropdownMenuItem(value: 5, child: Text(tr('5 secondi'))),
                ],
                onChanged: (v) => set(autoAnswerDelaySeconds: v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UiZoomCard extends StatelessWidget {
  const _UiZoomCard({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return ValueListenableBuilder<double>(
      valueListenable: appZoom,
      builder: (_, zoom, _) {
        final pct = (zoom * 100).round();
        return _Card(
          title: tr('Zoom interfaccia'),
          child: Row(
            children: [
              IconButton.outlined(
                tooltip: tr('Riduci zoom'),
                onPressed: zoom <= DrinScale.zoomMin
                    ? null
                    : () => phone.setZoom(zoom - DrinScale.zoomStep),
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              Expanded(
                child: Slider(
                  value: zoom.clamp(DrinScale.zoomMin, DrinScale.zoomMax),
                  min: DrinScale.zoomMin,
                  max: DrinScale.zoomMax,
                  divisions: 9,
                  label: '$pct %',
                  onChanged: phone.setZoom,
                ),
              ),
              IconButton.outlined(
                tooltip: tr('Aumenta zoom'),
                onPressed: zoom >= DrinScale.zoomMax
                    ? null
                    : () => phone.setZoom(zoom + DrinScale.zoomStep),
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
              const SizedBox(width: DrinSpace.s2),
              OutlinedButton(
                onPressed: zoom == 1.0 ? null : () => phone.setZoom(1.0),
                child: Text('$pct %', style: DrinText.number.copyWith(color: c.ink)),
              ),
            ],
          ),
        );
      },
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
          if (phone.installId.isNotEmpty)
            Row(
              children: [
                SelectableText(
                  tr('ID installazione: {id}', {'id': phone.installId}),
                  style: TextStyle(color: c.text),
                ),
                IconButton(
                  tooltip: tr('Copia'),
                  icon: Icon(Icons.copy_rounded, size: 16, color: c.muted),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: phone.installId)),
                ),
              ],
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

