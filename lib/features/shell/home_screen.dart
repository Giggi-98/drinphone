import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../account/account_dialog.dart';
import '../account/api_dialog.dart';
import '../call/call_panel.dart';
import '../call/keypad.dart';
import '../contacts/contacts_view.dart';
import '../history/history_view.dart';

/// Struttura a pannelli (proposta D): barra sezioni, barra composizione con
/// tastierino a comparsa, griglia interni. Gruppi: assenti di default (DECISIONS).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Section { extensions, contacts, history }

class _HomeScreenState extends State<HomeScreen> {
  final _dial = TextEditingController();
  bool _keypadOpen = false;
  _Section _section = _Section.extensions;
  late final AppLifecycleListener _lifecycle;

  PhoneController get p => widget.phone;

  @override
  void initState() {
    super.initState();
    p.addListener(_onPhone);
    // Chiudendo la finestra: revoca token API, un-REGISTER, flush del log.
    _lifecycle = AppLifecycleListener(
      // Rientro nella finestra: riallinea i dati PBX (saltato se letti da < 10 s).
      onResume: () => p.resync(force: false),
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
    _dial.dispose();
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

  // Invio nel campo: un numero si chiama; un nome chiama l'unico interno trovato.
  void _submit(String text) {
    final t = text.trim();
    if (RegExp(r'^[0-9*#+]+$').hasMatch(t)) return _call(t);
    final found = p.visibleExtensions.where(p.isCallable).toList();
    if (found.length == 1) _call(found.single.number);
  }

  void _call(String number) {
    p.dial(number);
    _dial.clear();
    p.setQuery('');
    setState(() => _keypadOpen = false);
  }

  void _openAccount() => showDialog<void>(
    context: context,
    builder: (_) => AccountDialog(phone: p),
  );

  void _openApi() => showDialog<void>(
    context: context,
    builder: (_) => ApiDialog(phone: p),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final call = p.call;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            section: _section,
            missed: p.history.where((r) => r.missed).length,
            onSection: (s) => setState(() => _section = s),
            onSettings: _openAccount,
            onApi: p.apiAvailable ? _openApi : null,
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(c),
                    if (p.engineError != null)
                      _banner(c, 'Motore SIP non avviato: ${p.engineError}'),
                    if (p.engineError == null && p.settings.account == null)
                      _banner(
                        c,
                        'Nessun account SIP configurato.',
                        action: ('Configura', _openAccount),
                      ),
                    Expanded(
                      child: switch (_section) {
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
                      },
                    ),
                  ],
                ),
                if (_keypadOpen)
                  Positioned(
                    top: 64,
                    right: 140,
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x47000000),
                            blurRadius: 32,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Keypad(
                        onKey: (d) => setState(() => _dial.text += d),
                      ),
                    ),
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
      RegistrationStatus.ok => (c.ok, 'Registrato'),
      RegistrationStatus.progress => (c.ringing, 'Registrazione…'),
      RegistrationStatus.failed => (c.busy, 'Errore registrazione'),
      _ => (c.muted, 'Non registrato'),
    };
    final account = p.settings.account;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: reg.message,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(color: c.text)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.field,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dial,
                    onSubmitted: _submit,
                    onChanged: (v) {
                      p.setQuery(v);
                      // La ricerca vale per interni e rubrica: dalla
                      // cronologia si torna agli interni.
                      if (_section == _Section.history && v.isNotEmpty) {
                        setState(() => _section = _Section.extensions);
                      }
                    },
                    style: TextStyle(
                      fontFamily: monoFont,
                      fontSize: 15,
                      color: c.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Numero, interno o nome',
                      // Il segnaposto eredita il monospazio del campo: lo riporta al testo normale.
                      hintStyle: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontSize: 14,
                        color: c.muted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                _iconButton(
                  c,
                  Icons.dialpad,
                  'Tastierino',
                  c.keyBtn,
                  c.accent,
                  () => setState(() => _keypadOpen = !_keypadOpen),
                ),
                const SizedBox(width: 4),
                _iconButton(
                  c,
                  Icons.call,
                  'Chiama',
                  DrinColors.callGreen,
                  Colors.white,
                  p.canDial ? () => _call(_dial.text) : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _openAccount,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: c.avatar,
                    child: Text(
                      account?.username ?? '?',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account == null
                            ? 'Nessun account'
                            : (account.displayName.isNotEmpty
                                  ? account.displayName
                                  : account.username),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: c.text,
                        ),
                      ),
                      Text(
                        account?.domain ?? 'Configura',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    DrinColors c,
    IconData icon,
    String tip,
    Color bg,
    Color fg,
    VoidCallback? onTap,
  ) => Tooltip(
    message: tip,
    child: Material(
      color: onTap == null ? c.keyBtn : bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: onTap == null ? c.muted : fg),
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.missed,
    required this.onSection,
    required this.onSettings,
    required this.onApi,
  });
  final _Section section;

  /// Chiamate perse in cronologia (badge).
  final int missed;
  final ValueChanged<_Section> onSection;
  final VoidCallback onSettings;
  final VoidCallback? onApi;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget item(
      IconData icon,
      String label,
      bool selected,
      VoidCallback? onTap,
    ) => Padding(
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
                const SizedBox(width: 12),
                Icon(icon, size: 18, color: selected ? c.accent : c.text),
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
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      width: 216,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'D',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'DrinPhone',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          item(
            Icons.people_outline,
            'Interni',
            section == _Section.extensions,
            () => onSection(_Section.extensions),
          ),
          item(
            Icons.contacts_outlined,
            'Rubrica',
            section == _Section.contacts,
            () => onSection(_Section.contacts),
          ),
          item(
            Icons.history,
            missed > 0 ? 'Cronologia · $missed perse' : 'Cronologia',
            section == _Section.history,
            () => onSection(_Section.history),
          ),
          const Spacer(),
          if (onApi != null)
            item(Icons.hub_outlined, 'Integrazione PBX', false, onApi),
          item(Icons.tune, 'Impostazioni', false, onSettings),
        ],
      ),
    );
  }
}

class _ExtensionsView extends StatelessWidget {
  const _ExtensionsView({required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi interno'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: number,
                decoration: const InputDecoration(
                  labelText: 'Numero / interno',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aggiungi'),
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

  String _groupTitle() {
    final g = phone.selectedGroup;
    if (g == null) return 'Tutti gli interni';
    final parts = g.split(':');
    final conn = phone.connections.where((c) => c.id == parts[0]).firstOrNull;
    if (conn == null) return 'Tutti gli interni';
    if (parts.length == 1) return conn.label;
    return conn.orgs.where((o) => '${o.id}' == parts[1]).firstOrNull?.name ??
        conn.label;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final list = phone.visibleExtensions;
    final grid = Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  phone.query.isEmpty
                      ? _groupTitle()
                      : 'Ricerca «${phone.query}» in ${_groupTitle()}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${list.length} interni',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi interno'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Nessun interno. Aggiungi quelli che chiami più spesso.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 116,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ExtensionCard(
                      ext: list[i],
                      canCall: phone.canDial,
                      callable: phone.isCallable(list[i]),
                      blf: phone.isCallable(list[i])
                          ? phone.blf[list[i].number]
                          : null,
                      presence: phone.presenceOf(list[i]),
                      onCall: () => onCall(list[i].number),
                      onRemove: phone.isManual(list[i])
                          ? () => phone.removeExtension(list[i])
                          : null,
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                phone.apiSummary.isEmpty
                    ? 'Stato interni via SIP BLF'
                    : 'Stato interni via SIP BLF · API PBX: ${phone.apiSummary}',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
    // Pannello reparti solo se un PBX li fornisce: di default non c'è (DECISIONS 2026-10-28).
    final hasGroups =
        phone.connections.length > 1 ||
        phone.connections.any((x) => x.orgs.isNotEmpty);
    if (!hasGroups) return grid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupsPanel(phone: phone),
        Expanded(child: grid),
      ],
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
    if (times.isEmpty) return 'mai sincronizzato';
    final t = times.reduce((a, b) => a.isBefore(b) ? a : b);
    String two(int n) => n.toString().padLeft(2, '0');
    return 'aggiornato alle ${two(t.hour)}:${two(t.minute)}';
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
            height: 38,
            child: Row(
              children: [
                // Barra di accento sulla voce selezionata.
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Guide verticali di rientro, una per livello.
                for (var d = 0; d < r.depth; d++)
                  SizedBox(
                    width: 16,
                    child: Center(
                      child: Container(width: 1, height: 38, color: c.border),
                    ),
                  ),
                SizedBox(
                  width: 24,
                  child: r.hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: open ? 'Chiudi' : 'Apri',
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
        borderRadius: BorderRadius.circular(12),
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
                        'Tutti gli interni',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 2, 6),
            child: Row(
              children: [
                Text(
                  'REPARTI',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Sincronizza ora · ${_lastSync()}',
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
                        : Icon(Icons.sync, color: c.muted),
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
                  'Sola lettura dal PBX',
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

class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.ext,
    required this.canCall,
    required this.callable,
    required this.blf,
    required this.presence,
    required this.onCall,
    required this.onRemove,
  });
  final Extension ext;
  final bool canCall;

  /// false = interno di un PBX senza account SIP in questa app.
  final bool callable;
  final BlfEvent? blf;
  final String presence;

  static const _presenceLabels = {
    'available': 'Disponibile',
    'away': 'Assente',
    'business_trip': 'In trasferta',
    'do_not_disturb': 'Non disturbare',
    'lunch': 'Pausa pranzo',
    'off_work': 'Fuori ufficio',
  };
  final VoidCallback onCall;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final initials = ext.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    // Libero/occupato pieni, squilla/sconosciuto ad anello: non solo colore.
    final (ring, fill, label, labelColor) = switch (blf?.status) {
      BlfStatus.idle => (c.ok, c.ok, 'Libero', c.okText),
      BlfStatus.busy => (c.busy, c.busy, 'Occupato', c.busyText),
      BlfStatus.ringing => (c.ringing, c.card, 'Squilla', c.ringing),
      BlfStatus.offline => (c.muted, c.card, 'Non registrato', c.muted),
      _ => (c.muted, c.card, 'Sconosciuto', c.muted),
    };
    final reason = blf?.reason ?? '';
    // Presenza Yeastar dopo lo stato linea: "Libero · Non disturbare".
    final presenceLabel = _presenceLabels[presence] ?? '';
    final detail = [
      if (reason.isNotEmpty) reason,
      if (presenceLabel.isNotEmpty) presenceLabel,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: c.avatar,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: fill,
                        shape: BoxShape.circle,
                        border: Border.all(color: ring, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Il nome si accorcia, il numero no.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ext.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: c.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ext.number,
                          style: TextStyle(
                            fontFamily: monoFont,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                    Tooltip(
                      message: reason,
                      child: Text(
                        detail.isEmpty ? label : '$label · $detail',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: labelColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: callable ? '' : 'Nessun account SIP su questo PBX',
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.keyBtn,
                      foregroundColor: c.accent,
                      minimumSize: const Size.fromHeight(36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: canCall && callable ? onCall : null,
                    icon: const Icon(Icons.call, size: 14),
                    label: const Text('Chiama'),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Interni dal PBX: si gestiscono sul PBX, qui non si rimuovono.
              if (onRemove != null)
                PopupMenuButton<void>(
                  tooltip: 'Altre azioni',
                  icon: Icon(Icons.more_horiz, color: c.muted),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: onRemove,
                      child: const Text('Rimuovi'),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
