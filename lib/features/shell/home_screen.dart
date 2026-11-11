import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/brand.dart';
import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/yeastar_api.dart' show YeastarApiException;
import '../../core/platform/call_links.dart';
import '../../core/platform/window_attention.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../call/call_window.dart';
import '../contacts/contacts_view.dart';
import '../history/history_view.dart';
import '../live/live_calls_view.dart';
import '../preferences/preferences_view.dart';
import '../setup/account_picker.dart';
import '../setup/setup_wizard.dart';
import '../voicemail/voicemail_view.dart';
import '../update/release_notes_dialog.dart';
import '../update/update_panel.dart';
import 'desktop_shell.dart';
import 'search_box.dart';
import 'shortcuts.dart';
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
  final _searchFocus = FocusNode();

  PhoneController get p => widget.phone;

  /// Sezioni nell'ordine del menu (Ctrl+1…5).
  List<_Section> get _menu => [
    _Section.extensions,
    if (p.hasLiveCalls) _Section.live,
    _Section.contacts,
    _Section.history,
    _Section.voicemail,
  ];

  void _go(_Section s) {
    setState(() => _section = s);
    _markSeen();
  }

  /// Scorciatoie globali (vedi shortcuts.dart): con Ctrl, attive con la
  /// finestra a fuoco anche dentro un campo di testo.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f1) {
      if (ModalRoute.of(context)?.isCurrent ?? true) showShortcuts(context);
      return true;
    }
    if (!ctrlOnly || !p.loggedIn) return false;
    final incoming = p.calls.values
        .where((c) => c.phase == CallPhase.incoming)
        .firstOrNull;
    final label = k.keyLabel.toLowerCase();
    if (label == 'k' || label == 'f' || label == 'l') {
      _searchFocus.requestFocus();
    } else if (label == ',') {
      _openPreferences();
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      if (incoming == null) return false;
      p.answer(incoming.id);
    } else if (label == 'e') {
      if (incoming != null) {
        p.hangup(incoming.id);
      } else if (p.call != null) {
        p.hangup();
      } else {
        return false;
      }
    } else if (label == 'm') {
      if (p.call == null) return false;
      p.toggleMute();
    } else if (label == 'h') {
      if (p.call == null) return false;
      p.toggleHold();
    } else if (digitOf(k) case final n?) {
      // Ctrl+0 è lo zoom: qui solo 1…9.
      if (n > _menu.length) return false;
      _go(_menu[n - 1]);
    } else {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    p.addListener(_onPhone);
    p.updater?.addListener(_onUpdater);
    // Finestre video permanenti, appena esiste la finestra dell'app; poi le
    // novità della versione, una volta sola dopo l'aggiornamento.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      p.attachVideoSurfaces();
      _showNewNotes();
      _onCallLink();
    });
    pendingCallLink.addListener(_onCallLink);
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(
      // Rientro nella finestra: riallinea i dati PBX (saltato se letti da < 10 s).
      onResume: () => p.resync(force: false),
      // Chiudendo la finestra: revoca token API, un-REGISTER, flush del log.
      onExitRequested: () async {
        // Chiudendo la finestra l'app resta nella barra di sistema (se
        // scelto); "Esci" dalla barra termina davvero.
        final shell = DesktopShell.instance;
        if (shell != null && !shell.quitting && p.settings.closeToTray) {
          WindowAttention.instance.hide();
          return AppExitResponse.cancel;
        }
        await p.shutdown();
        await shell?.dispose();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _searchFocus.dispose();
    pendingCallLink.removeListener(_onCallLink);
    p.removeListener(_onPhone);
    p.updater?.removeListener(_onUpdater);
    super.dispose();
  }

  Future<void> _showNewNotes() async {
    final u = p.updater;
    final notes = await u?.unseenNotes();
    if (u == null || notes == null || !mounted) return;
    // Segnate prima: chiudendo l'app col popup aperto non si ripresenta.
    await u.markNotesSeen();
    if (mounted) await showReleaseNotes(context, notes);
  }

  bool _linkDialog = false;

  /// Link tel:/sip: da browser o Outlook: si chiama solo dopo conferma (una
  /// pagina web può aprire un link verso qualunque numero).
  Future<void> _onCallLink() async {
    if (_linkDialog || pendingCallLink.value == null || !mounted) return;
    _linkDialog = true;
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CallLinkDialog(),
    );
    pendingCallLink.value = null;
    _linkDialog = false;
    if (number != null && number.isNotEmpty) _call(number);
  }

  /// Entrando (o restando) in Registro chiamate / Casella vocale il badge si spegne.
  void _markSeen() {
    if (_section == _Section.history) p.markHistorySeen();
    if (_section == _Section.voicemail) p.markVoicemailSeen();
  }

  void _onPhone() {
    _markSeen();
    final n = p.notice;
    if (n != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
      p.clearNotice();
    }
    setState(() {});
  }

  /// Voce "Aggiorna a …" nella barra laterale.
  void _onUpdater() => setState(() {});

  void _call(String number) => p.dial(number);

  /// Cambio presenza dal menu dell'header: solo lo stato del proprio interno.
  Future<void> _setPresence(String status) async {
    final d = p.ownDetail;
    if (d == null || status == p.ownPresence) return;
    try {
      await p.updateOwnExtension(d.withPresence(status));
    } catch (e) {
      if (!mounted) return;
      // Messaggio del PBX (operazione e codice), mai URL o token.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is YeastarApiException ? '$e' : tr('Salvataggio non riuscito'),
          ),
        ),
      );
    }
  }

  void _openPreferences([int tab = 0]) => setState(() {
    _prefsTab = tab;
    _section = _Section.preferences;
  });

  /// Primo avvio rimandato con "Configura più tardi" (fino al riavvio).
  bool _setupLater = false;

  Future<void> _logout() async {
    if (!await confirmDanger(
      context,
      title: tr('Uscire dall’account?'),
      body: tr(
        'L’interno si scollega dal PBX: le chiamate non arrivano più qui '
        'finché non rientri.',
      ),
      action: tr('Esci (logout)'),
    )) {
      return;
    }
    if (!mounted) return;
    if (!await p.logout() && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Non durante una chiamata'))));
      return;
    }
    setState(() => _section = _Section.extensions);
  }

  Future<void> _renameProfile() async {
    final ctl = TextEditingController(text: p.settings.profileName);
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
    if (name != null) await p.renameProfile(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    if (p.needsSetup && !_setupLater && p.engineError == null) {
      return SetupWizard(
        phone: p,
        firstRun: true,
        onDone: () => setState(() => _setupLater = true),
      );
    }
    if (!p.loggedIn) return AccountPicker(phone: p);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            section: _section == _Section.live && !p.hasLiveCalls
                ? _Section.extensions
                : _section,
            missed: p.missedUnseen,
            voicemailNew: p.voicemailUnseen,
            showLive: p.hasLiveCalls,
            live: p.connections.fold(0, (n, x) => n + x.visibleCalls.length),
            update: p.updater?.available?.version,
            onUpdate: () => showUpdateDialog(context, p, p.updater!),
            menu: _menu,
            onSection: _go,
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
                      child: AnimatedSectionSwitch(
                        child: switch (_section == _Section.live &&
                                !p.hasLiveCalls
                            ? _Section.extensions
                            : _section) {
                          _Section.extensions => _ExtensionsView(
                            key: const ValueKey('sec_ext'),
                            phone: p,
                            onCall: _call,
                          ),
                          _Section.contacts => ContactsView(
                            key: const ValueKey('sec_contacts'),
                            phone: p,
                            onCall: _call,
                          ),
                          _Section.history => HistoryView(
                            key: const ValueKey('sec_history'),
                            phone: p,
                            onCall: _call,
                          ),
                          _Section.voicemail => VoicemailView(
                            key: const ValueKey('sec_vm'),
                            phone: p,
                            onCall: _call,
                          ),
                          _Section.live => LiveCallsView(
                            key: const ValueKey('sec_live'),
                            phone: p,
                            onOpenPreferences: () => _openPreferences(5),
                          ),
                          _Section.preferences => PreferencesView(
                            key: ValueKey(('sec_prefs', _prefsTab)),
                            phone: p,
                            initialTab: _prefsTab,
                          ),
                        },
                      ),
                    ),
                  ],
                ),
                // Finestra di chiamata: in arrivo, in conversazione, ridotta.
                CallWindow(phone: p),
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
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.primary),
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
    final (dot, label) = switch (reg.status) {
      RegistrationStatus.ok => (c.ok, tr('Registrato')),
      RegistrationStatus.progress => (c.away, tr('Registrazione…')),
      RegistrationStatus.failed => (c.busy, tr('Errore registrazione')),
      _ => (c.muted, tr('Non registrato')),
    };
    final tooltip = [
      label,
      if (reg.message.isNotEmpty) reg.message,
    ].join(' · ');
    final account = p.settings.account;
    final presence = presenceOf(c, p.ownPresence);
    // La nota personalizzata del PBX spesso ripete solo lo stato
    // ("Available"): accanto al simbolo sarebbe un doppione in inglese.
    final rawNote = p.ownDetail?.customPresence.trim() ?? '';
    final noteKey = rawNote.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ');
    final customNote =
        presence != null &&
            (noteKey == p.ownPresence.replaceAll('_', ' ') ||
                noteKey == presence.$3.toLowerCase())
        ? ''
        : rawNote;
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
          // Stato della registrazione dell'account: pallino e testo breve.
          Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: _openPreferences,
              borderRadius: BorderRadius.circular(999),
              child: pill([
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, color: c.text)),
              ]),
            ),
          ),
          // Presenza del proprio interno: simbolo + colore bastano, testo nel
          // tooltip. Clic = menu per cambiarla subito (stessa scrittura di
          // Preferenze > Presenza, solo `presence_status` del proprio interno).
          if (presence != null) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '${tr('Stato di presenza')} · ${presence.$3}',
              position: PopupMenuPosition.under,
              onSelected: (v) =>
                  v == 'more' ? _openPreferences(1) : _setPresence(v),
              itemBuilder: (_) => [
                for (final st in presenceStatuses)
                  if (presenceOf(c, st) case final pr?)
                    PopupMenuItem(
                      value: st,
                      height: 40,
                      enabled: p.ownDetail != null,
                      child: Row(
                        children: [
                          Icon(pr.$1, size: 18, color: pr.$2),
                          const SizedBox(width: DrinSpace.s3),
                          Expanded(child: Text(pr.$3)),
                          if (st == p.ownPresence) ...[
                            const SizedBox(width: DrinSpace.s3),
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'more',
                  height: 40,
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 18, color: c.muted),
                      const SizedBox(width: DrinSpace.s3),
                      Text(tr('Impostazioni di presenza…')),
                    ],
                  ),
                ),
              ],
              child: pill([
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    presence.$1,
                    key: ValueKey(p.ownPresence),
                    size: 17,
                    color: presence.$2,
                  ),
                ),
                if (customNote.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      customNote,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.text),
                    ),
                  ),
                ],
              ]),
            ),
          ],
          const Spacer(),
          Flexible(
            child: SearchBox(phone: p, onCall: _call, focusNode: _searchFocus),
          ),
          const SizedBox(width: 12),
          // Account in uso (DECISIONS "Un account vivo alla volta").
          PopupMenuButton<String>(
            tooltip: tr('Account'),
            position: PopupMenuPosition.under,
            onSelected: (v) => switch (v) {
              'rename' => _renameProfile(),
              'logout' => _logout(),
              'lang:it' => p.setLanguage(AppLang.it),
              'lang:en' => p.setLanguage(AppLang.en),
              'theme:system' => p.setThemeMode(ThemeMode.system),
              'theme:light' => p.setThemeMode(ThemeMode.light),
              'theme:dark' => p.setThemeMode(ThemeMode.dark),
              _ => _openPreferences(),
            },
            itemBuilder: (_) {
              // Ogni voce: icona a sinistra, testo, spunta a destra se scelta;
              // stessi rientri per tutte.
              PopupMenuItem<String> item(
                String value,
                IconData icon,
                String label, {
                bool checked = false,
                bool enabled = true,
              }) => PopupMenuItem(
                value: value,
                enabled: enabled,
                height: 40,
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: c.muted),
                    const SizedBox(width: DrinSpace.s3),
                    Expanded(child: Text(label)),
                    if (checked) ...[
                      const SizedBox(width: DrinSpace.s3),
                      Icon(Icons.check_rounded, size: 18, color: c.primary),
                    ],
                  ],
                ),
              );
              return [
                item('prefs', Icons.tune_rounded, tr('Preferenze')),
                item('rename', Icons.edit_outlined, tr('Rinomina account…')),
                const PopupMenuDivider(),
                // Lingua e tema: si applicano subito, restando dove si è.
                for (final (l, label) in const [
                  (AppLang.it, 'Italiano'),
                  (AppLang.en, 'English'),
                ])
                  item(
                    'lang:${l.name}',
                    Icons.translate_rounded,
                    label,
                    checked: appLang.value == l,
                  ),
                const PopupMenuDivider(),
                for (final (m, icon, label) in [
                  (
                    ThemeMode.system,
                    Icons.brightness_auto_rounded,
                    tr('Tema di sistema'),
                  ),
                  (
                    ThemeMode.light,
                    Icons.light_mode_rounded,
                    tr('Tema chiaro'),
                  ),
                  (ThemeMode.dark, Icons.dark_mode_rounded, tr('Tema scuro')),
                ])
                  item(
                    'theme:${m.name}',
                    icon,
                    label,
                    checked: appThemeMode.value == m,
                  ),
                const PopupMenuDivider(),
                item(
                  'logout',
                  Icons.logout_rounded,
                  tr('Esci (logout)'),
                  enabled: p.calls.isEmpty,
                ),
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: c.avatar,
                    // Nome della persona dal PBX se c'è ("305" non dà iniziali).
                    child: initialsOrIcon(
                      p.primaryConnection?.directory
                              .where((e) => e.number == account?.username)
                              .firstOrNull
                              ?.name ??
                          account?.displayName ??
                          p.settings.profileName,
                      icon: Icons.person_rounded,
                      style: DrinText.label.copyWith(color: c.ink),
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
    required this.live,
    required this.menu,
    required this.onSection,
    this.update,
    this.onUpdate,
  });
  final _Section section;
  final int missed;
  final int voicemailNew;
  final bool showLive;

  /// Chiamate in corso sul PBX (badge neutro: è un'informazione, non un avviso).
  final int live;

  /// Ordine delle sezioni per Ctrl+1…5 (mostrato nel tooltip).
  final List<_Section> menu;
  final ValueChanged<_Section> onSection;

  /// Versione disponibile (aggiornamento non ancora installato).
  final String? update;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget sideItem(
      IconData icon,
      String label,
      bool selected,
      VoidCallback? onTap,
      Widget? trailing,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? c.keyBtn : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 3,
                    height: selected ? 20 : 0,
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
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
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
      ),
    );

    Widget item(
      IconData icon,
      String label,
      bool selected,
      VoidCallback? onTap, {
      Widget? trailing,
      _Section? of,
    }) {
      final n = of == null ? -1 : menu.indexOf(of);
      final keys = of == _Section.preferences
          ? 'Ctrl + ,'
          : n < 0
          ? null
          : 'Ctrl + ${n + 1}';
      final row = sideItem(icon, label, selected, onTap, trailing);
      return keys == null
          ? row
          : Tooltip(message: '$label · $keys', preferBelow: false, child: row);
    }

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DrinLogo(height: 36),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'DrinPhone',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ChannelBadge(),
                  ],
                ),
              ],
            ),
          ),
          item(
            Icons.grid_view_rounded,
            tr('Interni'),
            section == _Section.extensions,
            () => onSection(_Section.extensions),
            of: _Section.extensions,
          ),
          if (showLive)
            item(
              Icons.graphic_eq_rounded,
              tr('Chiamate in corso'),
              section == _Section.live,
              () => onSection(_Section.live),
              of: _Section.live,
              trailing: CountBadge(live),
            ),
          item(
            Icons.import_contacts_rounded,
            tr('Rubrica'),
            section == _Section.contacts,
            () => onSection(_Section.contacts),
            of: _Section.contacts,
          ),
          item(
            Icons.history_rounded,
            tr('Registro chiamate'),
            section == _Section.history,
            () => onSection(_Section.history),
            of: _Section.history,
            trailing: CountBadge(missed, alert: true),
          ),
          item(
            Icons.voicemail_rounded,
            tr('Casella vocale'),
            section == _Section.voicemail,
            () => onSection(_Section.voicemail),
            of: _Section.voicemail,
            trailing: CountBadge(voicemailNew, alert: true),
          ),
          const Spacer(),
          if (update != null)
            item(
              Icons.system_update_alt_rounded,
              tr('Aggiorna a {v}', {'v': update!}),
              false,
              onUpdate!,
            ),
          item(
            Icons.tune_rounded,
            tr('Preferenze'),
            section == _Section.preferences,
            () => onSection(_Section.preferences),
            of: _Section.preferences,
          ),
        ],
      ),
    );
  }
}

class _ExtensionsView extends StatefulWidget {
  const _ExtensionsView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<_ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends State<_ExtensionsView> {
  /// Togliere un preferito si annulla dall'avviso (aggiungerlo si vede).
  void _toggleFavorite(Extension e) {
    final was = phone.isFavorite(e);
    phone.toggleFavorite(e);
    if (!was) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('{n} tolto dai preferiti', {'n': e.number})),
          action: SnackBarAction(
            label: tr('Annulla'),
            onPressed: () => phone.toggleFavorite(e),
          ),
        ),
      );
  }

  int _page = 0;
  String? _pageGroup;
  BlfStatus? _blfFilter;

  /// Vista a righe dense invece delle schede; resta scelta tra le sezioni.
  static bool _compact = false;

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

  /// Pillola filtro BLF a soli simboli (il colore/icona indica già lo stato;
  /// la parola sta nel tooltip).
  Widget _filterChip(
    DrinColors c, {
    required BlfStatus? status,
    required String tooltip,
    required Widget symbol,
    required int count,
  }) {
    final selected = _blfFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() {
            _blfFilter = selected && status != null ? null : status;
            _page = 0;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? c.keyBtn : c.field,
              border: Border.all(color: selected ? c.accent : c.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                symbol,
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.accent : c.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    // Cambio gruppo: si riparte dalla prima pagina.
    if (_pageGroup != phone.selectedGroup) {
      _pageGroup = phone.selectedGroup;
      _page = 0;
    }
    final allInGroup = phone.visibleExtensions;
    final idleCount = allInGroup
        .where((e) => phone.blfOf(e) == BlfStatus.idle)
        .length;
    final busyCount = allInGroup
        .where((e) => phone.blfOf(e) == BlfStatus.busy)
        .length;
    final ringingCount = allInGroup
        .where((e) => phone.blfOf(e) == BlfStatus.ringing)
        .length;
    final list = _blfFilter == null
        ? allInGroup
        : allInGroup.where((e) => phone.blfOf(e) == _blfFilter).toList();
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
    Widget dot(Color color) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
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
              if (allInGroup.isNotEmpty) ...[
                _filterChip(
                  c,
                  status: null,
                  tooltip: tr('Tutti gli interni'),
                  symbol: Icon(
                    Icons.grid_view_rounded,
                    size: 14,
                    color: _blfFilter == null ? c.accent : c.muted,
                  ),
                  count: allInGroup.length,
                ),
                _filterChip(
                  c,
                  status: BlfStatus.idle,
                  tooltip: tr('Libero'),
                  symbol: dot(c.ok),
                  count: idleCount,
                ),
                _filterChip(
                  c,
                  status: BlfStatus.busy,
                  tooltip: tr('Occupato'),
                  symbol: dot(c.busy),
                  count: busyCount,
                ),
                if (ringingCount > 0 || _blfFilter == BlfStatus.ringing)
                  _filterChip(
                    c,
                    status: BlfStatus.ringing,
                    tooltip: tr('Squilla'),
                    symbol: Icon(
                      Icons.ring_volume_rounded,
                      size: 14,
                      color: c.ringing,
                    ),
                    count: ringingCount,
                  ),
                IconButton(
                  tooltip: _compact
                      ? tr('Vista a schede')
                      : tr('Vista a righe'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _compact = !_compact),
                  icon: Icon(
                    _compact
                        ? Icons.grid_view_rounded
                        : Icons.view_list_rounded,
                    size: 18,
                    color: c.muted,
                  ),
                ),
                IconButton(
                  tooltip: tr('Legenda degli stati'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showStatusLegend(context),
                  icon: Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: c.muted,
                  ),
                ),
              ],
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
                  selectedIcon: Icon(Icons.star_rounded, color: c.brand),
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
            child: AnimatedSectionSwitch(
              child: list.isEmpty
                  ? Center(
                      key: ValueKey(('empty', _pageGroup, _blfFilter)),
                      child: Text(
                        tr(
                          'Nessun interno. Aggiungi quelli che chiami più spesso.',
                        ),
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : GridView.builder(
                      key: ValueKey((
                        'grid',
                        _pageGroup,
                        _blfFilter,
                        _page,
                        _compact,
                      )),
                      // Schede (due righe: identità, poi pulsanti) o righe
                      // dense da 52 su più colonne (densità Centralino).
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: _compact ? 520 : 300,
                        mainAxisExtent: _compact ? 52 : 114,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: _compact ? 6 : 10,
                      ),
                      itemCount: slice.length,
                      itemBuilder: (_, i) {
                        final e = slice[i];
                        final dir = phone.primaryConnection?.directory
                            .where((x) => x.number == e.number)
                            .firstOrNull;
                        return _ExtensionTile(
                          details: [
                            if ((dir?.email ?? '').isNotEmpty)
                              (Icons.alternate_email_rounded, dir!.email),
                            if ((dir?.mobile ?? '').isNotEmpty)
                              (Icons.smartphone_rounded, dir!.mobile),
                          ],
                          compact: _compact,
                          ext: e,
                          callable: phone.isCallable(e),
                          canDial: phone.canDial,
                          blf: phone.blfOf(e),
                          blfStale: phone.blfStale(e),
                          presence: phone.presenceOf(e),
                          favorite: phone.isFavorite(e),
                          onFavorite: () => _toggleFavorite(e),
                          // Tramite l'account SIP del PBX dell'interno.
                          onCall: () => phone.dial(e.number, via: e),
                          onVideoCall: phone.videoEnabled
                              ? () => phone.dial(e.number, via: e, video: true)
                              : null,
                          onRemove: phone.isManual(e)
                              ? () => phone.removeExtension(e)
                              : null,
                        );
                      },
                    ),
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
    this.onVideoCall,
    required this.onRemove,
    this.compact = false,
    this.details = const [],
  });

  /// Email e cellulare dall'elenco del PBX, per la scheda al passaggio.
  final List<(IconData, String)> details;

  /// Riga densa (vista "righe"): tutto su una riga alta 52, azioni a destra.
  final bool compact;
  final Extension ext;
  final bool callable;
  final bool canDial;
  final BlfStatus? blf;
  final bool blfStale;
  final String presence;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onCall;

  /// Null se le videochiamate sono spente in Preferenze > Video.
  final VoidCallback? onVideoCall;
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
    final identity = Row(
      children: [
        StatusAvatar(
          name: ext.name,
          blf: blf,
          stale: w.blfStale,
          presence: w.presence,
          size: w.compact ? 32 : 40,
          details: w.details,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nameIsNumber(ext.name, ext.number))
                // Senza nome vero: il numero una volta sola.
                Text(
                  ext.number,
                  style: mono(blf == BlfStatus.offline ? c.muted : c.text),
                )
              else ...[
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
            ],
          ),
        ),
        if (onRemove != null)
          Tooltip(
            message: tr('Inserito a mano · tasto destro per rimuovere'),
            child: Icon(Icons.push_pin_outlined, size: 14, color: c.muted),
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
              color: favorite ? c.brand : c.muted,
            ),
          ),
      ],
    );
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
          // Tasto destro: tutte le azioni sull'interno.
          onSecondaryTapDown: (d) =>
              showActionsMenu(context, d.globalPosition, [
                (
                  Icons.call_rounded,
                  tr('Chiama'),
                  canDial && callable ? onCall : null,
                ),
                if (w.onVideoCall != null)
                  (
                    Icons.videocam_rounded,
                    tr('Videochiamata'),
                    canDial && callable ? w.onVideoCall : null,
                  ),
                copyAction(context, ext.number),
                (
                  favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  favorite
                      ? tr('Togli dai preferiti')
                      : tr('Aggiungi ai preferiti'),
                  onFavorite,
                ),
                if (onRemove != null) ...[
                  null,
                  (Icons.delete_outline_rounded, tr('Rimuovi'), onRemove),
                ],
              ]),
          child: Padding(
            padding: w.compact
                ? const EdgeInsets.fromLTRB(10, 0, 6, 0)
                : const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Flex(
              direction: w.compact ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: w.compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              children: [
                // Riga: l'identità occupa lo spazio fino alle azioni; scheda:
                // alta quanto serve, i pulsanti vanno in fondo (Spacer).
                if (w.compact) Expanded(child: identity) else identity,
                if (!w.compact) const Spacer(),
                // Pulsanti su una riga a parte: chiamata e videochiamata.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CallIconButton(
                      tooltip: callable
                          ? tr('Chiama {n}', {'n': ext.number})
                          : tr('Nessun account SIP su questo PBX'),
                      onPressed: canDial && callable ? onCall : null,
                    ),
                    if (w.onVideoCall != null) ...[
                      const SizedBox(width: 8),
                      CallIconButton(
                        icon: Icons.videocam_rounded,
                        tooltip: callable
                            ? tr('Videochiamata a {n}', {'n': ext.number})
                            : tr('Nessun account SIP su questo PBX'),
                        onPressed: canDial && callable ? w.onVideoCall : null,
                      ),
                    ],
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
      key: ValueKey('tree_${r.key}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? c.keyBtn : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => phone.selectGroup(r.key),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    width: 3,
                    height: selected ? 20 : 0,
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
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
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
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
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
                color: c.brand,
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
                  tr('Reparti'),
                  style: DrinText.label.copyWith(color: c.muted),
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

/// Conferma di un link telefonico. Il fuoco parte su Annulla e Chiama si
/// attiva dopo un attimo, anche a ogni numero nuovo arrivato col dialogo
/// aperto: un Invio pensato per un'altra finestra, o un link cambiato
/// all'ultimo, non fanno partire la chiamata.
class _CallLinkDialog extends StatefulWidget {
  const _CallLinkDialog();

  static const armDelay = Duration(milliseconds: 1200);

  @override
  State<_CallLinkDialog> createState() => _CallLinkDialogState();
}

class _CallLinkDialogState extends State<_CallLinkDialog> {
  String? _number;
  Timer? _arm;

  @override
  void initState() {
    super.initState();
    pendingCallLink.addListener(_onNumber);
    _onNumber();
  }

  void _onNumber() {
    final n = pendingCallLink.value;
    if (n == null || n == _number) return;
    _arm?.cancel();
    _arm = Timer(_CallLinkDialog.armDelay, () {
      if (mounted) setState(() => _arm = null);
    });
    if (mounted) setState(() => _number = n);
  }

  @override
  void dispose() {
    _arm?.cancel();
    pendingCallLink.removeListener(_onNumber);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _number ?? '';
    return AlertDialog(
      title: Text(tr('Chiamare {n}?', {'n': n})),
      content: Text(
        tr('Richiesta da un link aperto in un’altra applicazione.'),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla')),
        ),
        FilledButton.icon(
          onPressed: _arm != null ? null : () => Navigator.pop(context, n),
          icon: const Icon(Icons.call_rounded),
          label: Text(tr('Chiama')),
        ),
      ],
    );
  }
}
