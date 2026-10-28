import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../call/call_panel.dart';
import '../contacts/contacts_view.dart';
import '../history/history_view.dart';
import '../live/live_calls_view.dart';
import '../preferences/preferences_view.dart';
import '../setup/setup_wizard.dart';
import '../voicemail/voicemail_view.dart';
import 'search_box.dart';
import 'widgets.dart';

/// Struttura a pannelli (proposta D): barra sezioni, ricerca con popup e
/// tastierino, contenuto della sezione. Gruppi: assenti di default (DECISIONS).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Section { extensions, live, contacts, history, voicemail, preferences }

class _HomeScreenState extends State<HomeScreen> {
  _Section _section = _Section.extensions;

  /// Scheda iniziale delle Preferenze (5 = Integrazione PBX).
  int _prefsTab = 0;
  late final AppLifecycleListener _lifecycle;

  PhoneController get p => widget.phone;

  @override
  void initState() {
    super.initState();
    p.addListener(_onPhone);
    _lifecycle = AppLifecycleListener(
      // Rientro nella finestra: riallinea i dati PBX (saltato se letti da < 10 s).
      onResume: () => p.resync(force: false),
      // Chiudendo la finestra: revoca token API, un-REGISTER, flush del log.
      onExitRequested: () async {
        await p.shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    p.removeListener(_onPhone);
    super.dispose();
  }

  void _onPhone() {
    final n = p.notice;
    if (n != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
      p.clearNotice();
    }
    setState(() {});
  }

  void _call(String number) => p.dial(number);

  void _openPreferences([int tab = 0]) => setState(() {
    _prefsTab = tab;
    _section = _Section.preferences;
  });

  /// Primo avvio rimandato con "Configura più tardi" (fino al riavvio).
  bool _setupLater = false;

  void _newProfile() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => SetupWizard(
        phone: p,
        firstRun: false,
        onDone: () => Navigator.of(ctx).pop(),
      ),
    ),
  );

  Future<void> _switchProfile(String id) async {
    if (!await p.switchProfile(id) && mounted && p.calls.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Non durante una chiamata'))));
    }
    setState(() => _section = _Section.extensions);
  }

  Future<void> _renameProfile() async {
    final ctl = TextEditingController(text: p.settings.profileName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rinomina profilo')),
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
    if (name != null) await p.renameProfile(name);
  }

  Future<void> _deleteProfile(Profile prof) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminare il profilo {n}?', {'n': prof.name})),
        content: Text(
          tr(
            'Si cancellano i suoi account, le credenziali API, il registro '
            'chiamate e i contatti personali.',
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
    if (ok == true) await p.deleteProfile(prof.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final call = p.call;
    if (p.needsSetup && !_setupLater && p.engineError == null) {
      return SetupWizard(
        phone: p,
        firstRun: true,
        onDone: () => setState(() => _setupLater = true),
      );
    }
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            section: _section == _Section.live && !p.hasLiveCalls
                ? _Section.extensions
                : _section,
            missed: p.history.where((r) => r.missed).length,
            voicemailNew: p.voicemailNew,
            showLive: p.hasLiveCalls,
            onSection: (s) => setState(() => _section = s),
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(c),
                    if (p.engineError != null)
                      _banner(
                        c,
                        tr('Motore SIP non avviato: {e}', {
                          'e': p.engineError!,
                        }),
                      ),
                    if (p.engineError == null && p.settings.account == null)
                      _banner(
                        c,
                        tr('Nessun account SIP configurato.'),
                        action: (tr('Configura'), _openPreferences),
                      ),
                    Expanded(
                      // Live Calls sparisce senza eventi o nei profili SIP generici.
                      child: switch (_section == _Section.live &&
                              !p.hasLiveCalls
                          ? _Section.extensions
                          : _section) {
                        _Section.extensions => _ExtensionsView(
                          phone: p,
                          onCall: _call,
                        ),
                        _Section.contacts => ContactsView(
                          phone: p,
                          onCall: _call,
                        ),
                        _Section.history => HistoryView(
                          phone: p,
                          onCall: _call,
                        ),
                        _Section.voicemail => VoicemailView(
                          phone: p,
                          onCall: _call,
                        ),
                        _Section.live => LiveCallsView(
                          phone: p,
                          onOpenPreferences: () => _openPreferences(5),
                        ),
                        _Section.preferences => PreferencesView(
                          key: ValueKey(_prefsTab),
                          phone: p,
                          initialTab: _prefsTab,
                        ),
                      },
                    ),
                  ],
                ),
                if (call != null)
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: CallPanel(phone: p, call: call),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(DrinColors c, String text, {(String, VoidCallback)? action}) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.ringing),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.ringing),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: c.text)),
            ),
            if (action != null)
              TextButton(onPressed: action.$2, child: Text(action.$1)),
          ],
        ),
      );

  Widget _topBar(DrinColors c) {
    final reg = p.registration;
    var (dot, label) = switch (reg.status) {
      RegistrationStatus.ok => (c.ok, tr('Registrato')),
      RegistrationStatus.progress => (c.ringing, tr('Registrazione…')),
      RegistrationStatus.failed => (c.busy, tr('Errore registrazione')),
      _ => (c.muted, tr('Non registrato')),
    };
    // Più account: riepilogo "Registrati 2/3", dettaglio nel tooltip.
    final accounts = p.settings.accounts;
    var tooltip = reg.message;
    if (accounts.length > 1) {
      bool ok(SipAccount a) =>
          p.registrations[a.id]?.status == RegistrationStatus.ok;
      final n = accounts.where(ok).length;
      label = tr('Registrati {n}/{t}', {'n': n, 't': accounts.length});
      dot = n == accounts.length ? c.ok : (n == 0 ? c.busy : c.ringing);
      tooltip = [
        for (final a in accounts)
          '${a.username}@${a.domain}: ${p.registrations[a.id]?.status.name ?? '-'}',
      ].join('\n');
    }
    final account = p.settings.account;
    final via = p.outgoingAccount;
    Color dotOf(SipAccount a) => switch (p.registrations[a.id]?.status) {
      RegistrationStatus.ok => c.ok,
      RegistrationStatus.progress => c.ringing,
      RegistrationStatus.failed => c.busy,
      _ => c.muted,
    };
    final presence = presenceOf(c, p.ownPresence);
    Widget pill(List<Widget> children) => Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // "Chiama con" (come "Call Using" di Linkus): account per i numeri
          // liberi, con lo stato di registrazione.
          Tooltip(
            message: tooltip,
            child: PopupMenuButton<String>(
              tooltip: '',
              position: PopupMenuPosition.under,
              onSelected: (id) =>
                  id.isEmpty ? _openPreferences() : p.setCallWith(id),
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    tr('Chiama con'),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
                for (final a in accounts)
                  PopupMenuItem(
                    value: a.id,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: dotOf(a)),
                        const SizedBox(width: 10),
                        Text(
                          a.displayName.isNotEmpty
                              ? '${a.displayName} (${a.username})'
                              : a.username,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          a.domain,
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                        const SizedBox(width: 12),
                        if (a.id == via?.id)
                          Icon(Icons.check_rounded, size: 18, color: c.accent),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(value: '', child: Text(tr('Gestisci account…'))),
              ],
              child: pill([
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, color: c.text)),
                if (via != null) ...[
                  Text('  ·  ', style: TextStyle(color: c.muted)),
                  Icon(Icons.call_made_rounded, size: 14, color: c.muted),
                  const SizedBox(width: 4),
                  Text(
                    via.username,
                    style: mono(c.text, size: 12, weight: FontWeight.w600),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
              ]),
            ),
          ),
          // Presenza del proprio interno (dal PBX); dettaglio in Preferenze.
          if (presence != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: tr('Stato di presenza'),
              child: InkWell(
                onTap: () => _openPreferences(1),
                borderRadius: BorderRadius.circular(999),
                child: pill([
                  Icon(presence.$1, size: 16, color: presence.$2),
                  const SizedBox(width: 8),
                  Text(
                    presence.$3,
                    style: TextStyle(fontSize: 13, color: c.text),
                  ),
                ]),
              ),
            ),
          ],
          const Spacer(),
          SearchBox(phone: p, onCall: _call),
          const SizedBox(width: 12),
          // Profili (DECISIONS "Profili"): uno attivo alla volta.
          PopupMenuButton<String>(
            tooltip: tr('Profili'),
            position: PopupMenuPosition.under,
            onSelected: (v) => switch (v) {
              '+new' => _newProfile(),
              '+rename' => _renameProfile(),
              '+prefs' => _openPreferences(),
              _ when v.startsWith('-') => _deleteProfile(
                p.settings.others.firstWhere((x) => x.id == v.substring(1)),
              ),
              _ => _switchProfile(v),
            },
            itemBuilder: (_) => [
              for (final prof in p.settings.profiles)
                PopupMenuItem(
                  value: prof.id,
                  enabled: prof.id == p.settings.profileId || p.calls.isEmpty,
                  child: Row(
                    children: [
                      Icon(
                        prof.kind == ProfileKind.yeastar
                            ? Icons.hub_outlined
                            : Icons.dialpad_rounded,
                        size: 18,
                        color: c.muted,
                      ),
                      const SizedBox(width: 10),
                      Text(prof.name.isEmpty ? tr('Profilo') : prof.name),
                      const SizedBox(width: 8),
                      Text(
                        prof.kind == ProfileKind.yeastar
                            ? tr('Yeastar')
                            : tr('SIP generico'),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      const SizedBox(width: 12),
                      if (prof.id == p.settings.profileId)
                        Icon(Icons.check_rounded, size: 18, color: c.accent),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(value: '+new', child: Text(tr('Nuovo profilo…'))),
              PopupMenuItem(
                value: '+rename',
                child: Text(tr('Rinomina profilo…')),
              ),
              for (final prof in p.settings.others)
                PopupMenuItem(
                  value: '-${prof.id}',
                  child: Text(tr('Elimina profilo {n}…', {'n': prof.name})),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(value: '+prefs', child: Text(tr('Preferenze'))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: c.avatar,
                    child: Text(
                      account?.username ?? '?',
                      style: mono(c.text, size: 11, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account == null
                            ? tr('Nessun account')
                            : (account.displayName.isNotEmpty
                                  ? account.displayName
                                  : account.username),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                      Text(
                        [
                          if (p.settings.profileName.isNotEmpty)
                            p.settings.profileName,
                          account?.domain ?? tr('Configura'),
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.missed,
    required this.voicemailNew,
    required this.showLive,
    required this.onSection,
  });
  final _Section section;
  final int missed;
  final int voicemailNew;
  final bool showLive;
  final ValueChanged<_Section> onSection;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget item(
      IconData icon,
      String label,
      bool selected,
      VoidCallback? onTap, {
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.keyBtn : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20, color: selected ? c.accent : c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? c.accent : c.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                ?trailing,
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      width: 228,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.14),
                    border: Border.all(color: c.accent, width: 1.5),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    'D',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'DrinPhone',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          item(
            Icons.people_alt_outlined,
            tr('Interni'),
            section == _Section.extensions,
            () => onSection(_Section.extensions),
          ),
          if (showLive)
            item(
              Icons.monitor_heart_outlined,
              tr('Live Calls'),
              section == _Section.live,
              () => onSection(_Section.live),
            ),
          item(
            Icons.contacts_outlined,
            tr('Rubrica'),
            section == _Section.contacts,
            () => onSection(_Section.contacts),
          ),
          item(
            Icons.history_rounded,
            tr('Registro chiamate'),
            section == _Section.history,
            () => onSection(_Section.history),
            trailing: CountBadge(missed, alert: true),
          ),
          item(
            Icons.voicemail_rounded,
            tr('Casella vocale'),
            section == _Section.voicemail,
            () => onSection(_Section.voicemail),
            trailing: CountBadge(voicemailNew, alert: true),
          ),
          const Spacer(),
          item(
            Icons.tune_rounded,
            tr('Preferenze'),
            section == _Section.preferences,
            () => onSection(_Section.preferences),
          ),
        ],
      ),
    );
  }
}

class _ExtensionsView extends StatefulWidget {
  const _ExtensionsView({required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<_ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends State<_ExtensionsView> {
  int _page = 0;
  String? _pageGroup;

  PhoneController get phone => widget.phone;

  /// Schede per pagina: abbastanza per riempire uno schermo grande.
  static const pageSize = 60;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Aggiungi interno')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: tr('Nome')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: number,
                decoration: InputDecoration(labelText: tr('Numero / interno')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Annulla')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Aggiungi')),
          ),
        ],
      ),
    );
    if (ok == true && number.text.trim().isNotEmpty) {
      final n = number.text.trim();
      await phone.addExtension(
        Extension(name.text.trim().isEmpty ? n : name.text.trim(), n),
      );
    }
    name.dispose();
    number.dispose();
  }

  static bool _hasGroups(PhoneController p) =>
      p.connections.length > 1 || p.connections.any((x) => x.orgs.isNotEmpty);

  String _groupTitle() {
    final g = phone.selectedGroup;
    if (g == null) return tr('Tutti gli interni');
    if (g == PhoneController.favoritesGroup) return tr('Preferiti');
    final parts = g.split(':');
    final conn = phone.connections.where((c) => c.id == parts[0]).firstOrNull;
    if (conn == null) return tr('Tutti gli interni');
    if (parts.length == 1) return conn.label;
    return conn.orgs.where((o) => '${o.id}' == parts[1]).firstOrNull?.name ??
        conn.label;
  }

  /// Reparto selezionato (`<pbx>:<org>`), non un PBX intero o i Preferiti.
  static bool _isOrg(String? g) => g != null && g.split(':').length > 1;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    // Cambio gruppo: si riparte dalla prima pagina.
    if (_pageGroup != phone.selectedGroup) {
      _pageGroup = phone.selectedGroup;
      _page = 0;
    }
    final list = phone.visibleExtensions;
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
    final grid = Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _groupTitle(),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    CountBadge(list.length),
                  ],
                ),
              ),
              if (_isOrg(phone.selectedGroup))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: phone.directMembersOnly,
                        onChanged: (v) =>
                            phone.setDirectMembersOnly(v ?? false),
                      ),
                      Text(
                        tr('Solo membri diretti'),
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ],
                  ),
                ),
              // Senza pannello reparti, il filtro Preferiti sta nell'intestazione.
              if (!_hasGroups(phone))
                IconButton(
                  tooltip: tr('Preferiti'),
                  isSelected:
                      phone.selectedGroup == PhoneController.favoritesGroup,
                  onPressed: () => phone.selectGroup(
                    phone.selectedGroup == PhoneController.favoritesGroup
                        ? null
                        : PhoneController.favoritesGroup,
                  ),
                  icon: Icon(Icons.star_border_rounded, color: c.muted),
                  selectedIcon: Icon(Icons.star_rounded, color: c.ringing),
                ),
              // Aggiunta manuale solo nel contesto "Tutti gli interni".
              if (phone.selectedGroup == null)
                IconButton.filledTonal(
                  tooltip: tr('Aggiungi interno'),
                  style: IconButton.styleFrom(
                    backgroundColor: c.keyBtn,
                    foregroundColor: c.accent,
                  ),
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      tr(
                        'Nessun interno. Aggiungi quelli che chiami più spesso.',
                      ),
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisExtent: 72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: slice.length,
                    itemBuilder: (_, i) {
                      final e = slice[i];
                      return _ExtensionTile(
                        ext: e,
                        callable: phone.isCallable(e),
                        canDial: phone.canDial,
                        blf: phone.blfOf(e),
                        blfStale: phone.blfStale(e),
                        presence: phone.presenceOf(e),
                        favorite: phone.isFavorite(e),
                        onFavorite: () => phone.toggleFavorite(e),
                        // Tramite l'account SIP del PBX dell'interno.
                        onCall: () => phone.dial(e.number, via: e),
                        onRemove: phone.isManual(e)
                            ? () => phone.removeExtension(e)
                            : null,
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Pager(
            total: list.length,
            page: _page,
            pageSize: pageSize,
            onPage: (i) => setState(() => _page = i),
          ),
          if (phone.apiSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                phone.apiSummary,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
            ),
        ],
      ),
    );
    // Pannello reparti solo se un PBX li fornisce: di default non c'è (DECISIONS 2026-10-28).
    if (!_hasGroups(phone)) return grid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupsPanel(phone: phone),
        Expanded(child: grid),
      ],
    );
  }
}

/// Scheda compatta: avatar (stato linea + presenza), nome, numero, simbolo di chiamata.
/// La stella dei preferiti compare al passaggio del mouse o se già preferito.
class _ExtensionTile extends StatefulWidget {
  const _ExtensionTile({
    required this.ext,
    required this.callable,
    required this.canDial,
    required this.blf,
    this.blfStale = false,
    required this.presence,
    required this.favorite,
    required this.onFavorite,
    required this.onCall,
    required this.onRemove,
  });
  final Extension ext;
  final bool callable;
  final bool canDial;
  final BlfStatus? blf;
  final bool blfStale;
  final String presence;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onCall;
  final VoidCallback? onRemove;

  @override
  State<_ExtensionTile> createState() => _ExtensionTileState();
}

class _ExtensionTileState extends State<_ExtensionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final w = widget;
    final ext = w.ext, blf = w.blf, onRemove = w.onRemove;
    final callable = w.callable, canDial = w.canDial, onCall = w.onCall;
    final favorite = w.favorite, onFavorite = w.onFavorite;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // Doppio clic sulla scheda = chiama, come nei softphone desktop.
          onDoubleTap: canDial && callable ? onCall : null,
          onSecondaryTapDown: onRemove == null
              ? null
              : (d) => showMenu<void>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    d.globalPosition.dx,
                    d.globalPosition.dy,
                    d.globalPosition.dx,
                    d.globalPosition.dy,
                  ),
                  items: [
                    PopupMenuItem(onTap: onRemove, child: Text(tr('Rimuovi'))),
                  ],
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                StatusAvatar(
                  name: ext.name,
                  blf: blf,
                  stale: w.blfStale,
                  presence: w.presence,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ext.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: blf == BlfStatus.offline ? c.muted : c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(ext.number, style: mono(c.muted, size: 12)),
                    ],
                  ),
                ),
                if (onRemove != null)
                  Tooltip(
                    message: tr('Inserito a mano · tasto destro per rimuovere'),
                    child: Icon(
                      Icons.push_pin_outlined,
                      size: 14,
                      color: c.muted,
                    ),
                  ),
                if (favorite || _hover)
                  IconButton(
                    tooltip: favorite
                        ? tr('Togli dai preferiti')
                        : tr('Aggiungi ai preferiti'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 20,
                      color: favorite ? c.ringing : c.muted,
                    ),
                  ),
                CallIconButton(
                  tooltip: callable
                      ? tr('Chiama {n}', {'n': ext.number})
                      : tr('Nessun account SIP su questo PBX'),
                  onPressed: canDial && callable ? onCall : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una riga dell'albero reparti, già appiattita.
class _TreeRow {
  const _TreeRow({
    required this.key,
    required this.label,
    required this.depth,
    required this.count,
    required this.icon,
    required this.hasChildren,
  });
  final String key;
  final String label;
  final int depth;
  final int count;
  final IconData icon;
  final bool hasChildren;
}

class _GroupsPanel extends StatefulWidget {
  const _GroupsPanel({required this.phone});
  final PhoneController phone;

  @override
  State<_GroupsPanel> createState() => _GroupsPanelState();
}

class _GroupsPanelState extends State<_GroupsPanel> {
  /// Nodi chiusi (chiave come in PhoneController.selectedGroup).
  final _collapsed = <String>{};

  PhoneController get phone => widget.phone;

  List<_TreeRow> _rows() {
    final multi = phone.connections.length > 1;
    final rows = <_TreeRow>[];
    for (final conn in phone.connections) {
      final base = multi ? 1 : 0;
      if (multi) {
        rows.add(
          _TreeRow(
            key: conn.id,
            label: conn.label,
            depth: 0,
            count: conn.directory.length,
            icon: Icons.dns_outlined,
            hasChildren: conn.orgs.isNotEmpty,
          ),
        );
        if (_collapsed.contains(conn.id)) continue;
      }
      final byId = {for (final o in conn.orgs) o.id: o};
      final parents = {for (final o in conn.orgs) o.parentId};
      bool hidden(int parentId) {
        for (var p = parentId; p != 0; p = byId[p]?.parentId ?? 0) {
          if (_collapsed.contains('${conn.id}:$p')) return true;
        }
        return false;
      }

      for (final o in conn.orgs) {
        if (hidden(o.parentId)) continue;
        final hasChildren = parents.contains(o.id);
        rows.add(
          _TreeRow(
            key: '${conn.id}:${o.id}',
            label: o.name,
            depth: base + o.depth,
            count: o.extIds.length,
            icon: o.depth == 0
                ? Icons.apartment_outlined
                : hasChildren
                ? Icons.account_tree_outlined
                : Icons.groups_outlined,
            hasChildren: hasChildren,
          ),
        );
      }
    }
    return rows;
  }

  String _lastSync() {
    final times = [for (final c in phone.connections) c.lastSync].nonNulls;
    if (times.isEmpty) return tr('mai sincronizzato');
    final t = times.reduce((a, b) => a.isBefore(b) ? a : b);
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('aggiornato alle {t}', {'t': '${two(t.hour)}:${two(t.minute)}'});
  }

  Widget _pill(DrinColors c, int n, bool selected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: selected ? c.accent.withValues(alpha: 0.18) : c.keyBtn,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$n',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? c.accent : (n == 0 ? c.muted : c.text),
      ),
    ),
  );

  Widget _row(DrinColors c, _TreeRow r) {
    final selected = phone.selectedGroup == r.key;
    final open = !_collapsed.contains(r.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.keyBtn : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => phone.selectGroup(r.key),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                for (var d = 0; d < r.depth; d++)
                  SizedBox(
                    width: 16,
                    child: Center(
                      child: Container(width: 1, height: 36, color: c.border),
                    ),
                  ),
                SizedBox(
                  width: 24,
                  child: r.hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: open ? tr('Chiudi') : tr('Apri'),
                          onPressed: () => setState(
                            () => open
                                ? _collapsed.add(r.key)
                                : _collapsed.remove(r.key),
                          ),
                          icon: AnimatedRotation(
                            turns: open ? 0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(Icons.chevron_right, color: c.muted),
                          ),
                        )
                      : null,
                ),
                Icon(r.icon, size: 18, color: selected ? c.accent : c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? c.accent : c.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                _pill(c, r.count, selected),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _favoritesRow(DrinColors c) {
    final on = phone.selectedGroup == PhoneController.favoritesGroup;
    return Material(
      color: on ? c.keyBtn : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => phone.selectGroup(PhoneController.favoritesGroup),
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                on ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: c.ringing,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Preferiti'),
                  style: TextStyle(
                    color: on ? c.accent : c.text,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              _pill(c, phone.favorites.length, on),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final syncing = phone.connections.any((x) => x.syncing);
    final allSelected = phone.selectedGroup == null;
    return Container(
      width: 260,
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: allSelected ? c.keyBtn : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => phone.selectGroup(null),
              child: SizedBox(
                height: 42,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(
                      Icons.people_alt_outlined,
                      size: 18,
                      color: allSelected ? c.accent : c.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('Tutti gli interni'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: allSelected ? c.accent : c.text,
                          fontWeight: allSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    _pill(c, phone.allExtensions.length, allSelected),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          _favoritesRow(c),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 2, 6),
            child: Row(
              children: [
                Text(
                  tr('REPARTI'),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: '${tr('Sincronizza ora')} · ${_lastSync()}',
                  child: IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: syncing ? null : () => phone.resync(),
                    icon: syncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.sync_rounded, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(children: [for (final r in _rows()) _row(c, r)]),
          ),
          Divider(color: c.border, height: 16),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('Sola lettura dal PBX'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
