import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../account/api_dialog.dart';
import '../preferences/preferences_view.dart';

/// Procedura guidata (DECISIONS "Profili"): al primo avvio configura il
/// profilo vuoto; da "Nuovo profilo…" ne crea uno. Passi: lingua (solo primo
/// avvio) → tipo e nome → account con stato di registrazione → API (solo
/// Yeastar, facoltative) → audio.
class SetupWizard extends StatefulWidget {
  const SetupWizard({
    super.key,
    required this.phone,
    required this.firstRun,
    required this.onDone,
  });
  final PhoneController phone;
  final bool firstRun;
  final VoidCallback onDone;

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

enum _Step { language, kind, accounts, api, audio }

class _SetupWizardState extends State<SetupWizard> {
  late _Step _step = widget.firstRun ? _Step.language : _Step.kind;
  ProfileKind _kind = ProfileKind.yeastar;
  final _name = TextEditingController();

  /// Profilo da cui si è partiti con "Nuovo profilo…" (per annullare).
  String? _previous;
  String? _created;

  PhoneController get p => widget.phone;

  List<_Step> get _steps => [
    if (widget.firstRun) _Step.language,
    _Step.kind,
    _Step.accounts,
    if (_kind == ProfileKind.yeastar) _Step.api,
    _Step.audio,
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step == _Step.kind) {
      final name = _name.text.trim().isNotEmpty
          ? _name.text.trim()
          : (_kind == ProfileKind.yeastar ? 'Yeastar' : 'SIP');
      if (widget.firstRun) {
        await p.renameProfile(name, kind: _kind);
      } else if (_created == null) {
        _previous = p.settings.profileId;
        if (!await p.createProfile(name, _kind)) return;
        _created = p.settings.profileId;
      } else {
        await p.renameProfile(name, kind: _kind);
      }
    }
    final i = _steps.indexOf(_step);
    if (i == _steps.length - 1) {
      widget.onDone();
    } else {
      setState(() => _step = _steps[i + 1]);
    }
  }

  void _back() {
    final i = _steps.indexOf(_step);
    if (i > 0) setState(() => _step = _steps[i - 1]);
  }

  /// Annulla: un profilo appena creato si elimina e si torna al precedente.
  Future<void> _cancel() async {
    final prev = _previous, created = _created;
    if (prev != null && created != null) {
      await p.switchProfile(prev);
      await p.deleteProfile(created);
    }
    widget.onDone();
  }

  bool get _canGoOn =>
      _step != _Step.accounts || p.settings.accounts.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final steps = _steps;
    return Scaffold(
      backgroundColor: c.ground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListenableBuilder(
              listenable: p,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.firstRun
                              ? tr('Benvenuto in DrinPhone')
                              : tr('Nuovo profilo'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        tr('Passo {i} di {n}', {
                          'i': steps.indexOf(_step) + 1,
                          'n': steps.length,
                        }),
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (steps.indexOf(_step) + 1) / steps.length,
                    color: c.accent,
                    backgroundColor: c.field,
                  ),
                  const SizedBox(height: 24),
                  Expanded(child: SingleChildScrollView(child: _body(c))),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        child: Text(
                          widget.firstRun
                              ? tr('Configura più tardi')
                              : tr('Annulla'),
                        ),
                      ),
                      const Spacer(),
                      if (steps.indexOf(_step) > 0)
                        TextButton(
                          onPressed: _back,
                          child: Text(tr('Indietro')),
                        ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _canGoOn ? _next : null,
                        child: Text(
                          _step == steps.last
                              ? tr('Fine')
                              : (_step == _Step.api
                                    ? tr('Avanti / salta')
                                    : tr('Avanti')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(DrinColors c, String t, [String sub = '']) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: c.muted)),
        ],
      ],
    ),
  );

  Widget _choice(
    DrinColors c, {
    required bool selected,
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? c.keyBtn : c.card,
          border: Border.all(color: selected ? c.accent : c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: selected ? c.accent : c.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: c.accent),
          ],
        ),
      ),
    ),
  );

  Widget _body(DrinColors c) => switch (_step) {
    _Step.language => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(c, tr('Lingua')),
        for (final l in AppLang.values)
          _choice(
            c,
            selected: appLang.value == l,
            icon: Icons.translate_rounded,
            title: l == AppLang.it ? 'Italiano' : 'English',
            sub: l == AppLang.it
                ? 'Interfaccia in italiano'
                : 'English interface',
            onTap: () => p.setLanguage(l),
          ),
      ],
    ),
    _Step.kind => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(c, tr('Che centralino usi?')),
        _choice(
          c,
          selected: _kind == ProfileKind.yeastar,
          icon: Icons.hub_outlined,
          title: tr('Yeastar P-Series (integrato)'),
          sub: tr(
            'Fino a 3 PBX Yeastar; interni, rubrica aziendale, presenza e Live '
            'Calls dalle API (facoltative).',
          ),
          onTap: () => setState(() => _kind = ProfileKind.yeastar),
        ),
        _choice(
          c,
          selected: _kind == ProfileKind.sip,
          icon: Icons.dialpad_rounded,
          title: tr('Altro PBX o trunk SIP'),
          sub: tr(
            'Qualunque centralino SIP o trunk VoIP diretto: interni e contatti '
            'li crei tu.',
          ),
          onTap: () => setState(() => _kind = ProfileKind.sip),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: tr('Nome del profilo'),
            hintText: _kind == ProfileKind.yeastar ? 'Econnet' : 'Trunk VoIP',
          ),
        ),
      ],
    ),
    _Step.accounts => _accounts(c),
    _Step.api => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          c,
          tr('Integrazione API (facoltativa)'),
          tr(
            'Con Client ID e Secret del PBX arrivano interni, reparti, rubrica, '
            'presenza e Live Calls. Si può fare anche dopo, da Preferenze.',
          ),
        ),
        PbxConnectionsPanel(phone: p),
      ],
    ),
    _Step.audio => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(c, tr('Audio')),
        AudioSettings(phone: p),
      ],
    ),
  };

  Widget _accounts(DrinColors c) {
    final accounts = p.settings.accounts;
    final yeastar = _kind == ProfileKind.yeastar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          c,
          yeastar ? tr('Account SIP dei PBX Yeastar') : tr('Account SIP'),
          yeastar
              ? tr(
                  'Un account (interno) per ogni PBX, fino a 3. Un trunk VoIP '
                  'aggiunto qui serve solo per chiamare.',
                )
              : tr('Server, utente e password del centralino o del trunk.'),
        ),
        for (final a in accounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.circle,
              size: 12,
              color: switch (p.registrations[a.id]?.status) {
                RegistrationStatus.ok => c.ok,
                RegistrationStatus.progress => c.ringing,
                RegistrationStatus.failed => c.busy,
                _ => c.muted,
              },
            ),
            title: Text('${a.username}@${a.domain}'),
            subtitle: Text(switch (p.registrations[a.id]?.status) {
              RegistrationStatus.ok => tr('Registrato'),
              RegistrationStatus.progress => tr('Registrazione…'),
              RegistrationStatus.failed =>
                '${tr('Errore registrazione')} · ${p.registrations[a.id]?.message ?? ''}',
              _ => tr('Non registrato'),
            }, style: TextStyle(color: c.muted)),
            trailing: IconButton(
              tooltip: tr('Modifica'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AccountEditor(phone: p, account: a),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AccountEditor(phone: p),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              accounts.isEmpty
                  ? tr('Aggiungi account')
                  : (yeastar
                        ? tr('Aggiungi un altro PBX o un trunk')
                        : tr('Aggiungi account')),
            ),
          ),
        ),
      ],
    );
  }
}
