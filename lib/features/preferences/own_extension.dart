part of 'preferences_view.dart';

// Proprio interno sul PBX Yeastar: presenze, inoltri, squillo, casella vocale.
// Le modifiche restano in bozza finché non si preme "Salva sul PBX"; partono
// solo i campi utente ammessi e solo sul proprio interno (DECISIONS "Scrittura
// sul proprio interno", YeastarApi.ownWritable).

const _statuses = [
  'available',
  'away',
  'business_trip',
  'do_not_disturb',
  'lunch',
  'off_work',
];

/// Destinazioni che si possono scegliere; le altre (IVR, code, gruppi,
/// messaggi registrati) si tengono se già impostate sul PBX.
const _pickableDests = [
  'ext_vm',
  'extension',
  'mobile_number',
  'external_num',
  'end_call',
  'send_busy',
];

String _destLabel(String dest) => switch (dest) {
  'extension' => tr('Interno'),
  'ext_vm' => tr('Casella vocale'),
  'mobile_number' => tr('Cellulare'),
  'external_num' => tr('Numero esterno'),
  'ivr' => 'IVR',
  'queue' => tr('Coda'),
  'ring_group' => tr('Gruppo di squillo'),
  'call_flow' => 'Call flow',
  'group_vm' => tr('Casella vocale di gruppo'),
  'play_greeting' => tr('Messaggio registrato'),
  'end_call' => tr('Termina la chiamata'),
  'send_busy' => tr('Segnale di occupato'),
  _ => dest,
};

/// Bozza delle modifiche al proprio interno e barra "Salva sul PBX".
mixin _OwnExtensionDraft<T extends StatefulWidget> on State<T> {
  PhoneController get phone;
  PbxExtensionDetail? _draft;
  bool _saving = false;
  String? _error;

  PbxExtensionDetail? get detail => _draft ?? phone.ownDetail;

  bool get dirty {
    final d = _draft, o = phone.ownDetail;
    return d != null && o != null && d.changesFrom(o).isNotEmpty;
  }

  /// Motivo per cui la bozza non si può salvare ('' = si può).
  String get invalid {
    for (final p in detail?.presences ?? const <PresenceSetting>[]) {
      for (final f in p.forwards.values) {
        if (!f.enabled) continue;
        if (f.dest == 'extension' && f.value.isEmpty) {
          return tr('Scegli l\'interno di destinazione');
        }
        if (f.dest == 'external_num' &&
            !RegExp(r'^[0-9+*#]{2,31}$').hasMatch(f.number)) {
          return tr('Numero esterno non valido');
        }
      }
    }
    return '';
  }

  void edit(PbxExtensionDetail d) => setState(() {
    _draft = d;
    _error = null;
  });

  Future<void> save([PbxExtensionDetail? d]) async {
    final edited = d ?? _draft;
    if (edited == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await phone.updateOwnExtension(edited);
      _draft = null;
    } catch (e) {
      // Messaggio del PBX (operazione e codice), mai URL o token.
      _error = e is YeastarApiException ? '$e' : tr('Salvataggio non riuscito');
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget saveBar(DrinColors c) {
    if (!dirty && _error == null) return const SizedBox.shrink();
    final why = invalid;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.10),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error ??
                  (why.isNotEmpty
                      ? why
                      : tr('Modifiche non ancora salvate sul PBX')),
              style: TextStyle(
                color: _error != null || why.isNotEmpty ? c.busyText : c.text,
              ),
            ),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _draft = null;
                    _error = null;
                  }),
            child: Text(tr('Annulla')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving || !dirty || why.isNotEmpty ? null : save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(tr('Salva sul PBX')),
          ),
        ],
      ),
    );
  }

  Widget toggle(
    DrinColors c,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String help = '',
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: value,
    onChanged: _saving ? null : onChanged,
    title: Text(label, style: TextStyle(color: c.text)),
    subtitle: help.isEmpty
        ? null
        : Text(help, style: TextStyle(fontSize: 12, color: c.muted)),
  );

  Widget choice<V>(
    String label,
    V value,
    Map<V, String> options,
    ValueChanged<V> onChanged, {
    double width = 260,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<V>(
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving
          ? null
          : (v) {
              if (v != null) onChanged(v);
            },
    ),
  );
}

// ----------------------------------------------------------------- Presenza

/// Presenza in profondità (stile Linkus): stato attuale, le sei presenze con
/// inoltri e squillo, cambio automatico per orario, più dispositivi.
class _PresenceTab extends StatefulWidget {
  const _PresenceTab({required this.phone});
  final PhoneController phone;

  @override
  State<_PresenceTab> createState() => _PresenceTabState();
}

class _PresenceTabState extends State<_PresenceTab>
    with _OwnExtensionDraft<_PresenceTab> {
  @override
  PhoneController get phone => widget.phone;

  /// Presenza di cui si guardano le impostazioni (null = quella attuale).
  String? _viewed;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await phone.refreshOwnDetail();
    if (mounted) setState(() => _refreshing = false);
  }

  void _setForward(PresenceSetting s, String cond, PresenceForward f) =>
      edit(detail!.withSetting(s.withForward(cond, f)));

  void _setValues(PresenceSetting s, Map<String, Object> v) =>
      edit(detail!.withSetting(s.withValues(v)));

  Widget _forward(DrinColors c, PresenceSetting s, String cond, String label) {
    final f = s.forwards[cond]!;
    final dir = (phone.primaryConnection?.directory ?? const <PbxExtension>[])
        .where((e) => e.number != phone.settings.account?.username)
        .toList();
    final dests = {
      for (final d in [..._pickableDests, if (f.dest.isNotEmpty) f.dest])
        d: _destLabel(d),
    };
    PresenceForward to(String dest) => PresenceForward(
      enabled: f.enabled,
      dest: dest,
      prefix: f.prefix,
      callConfirm: f.callConfirm,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          SizedBox(
            width: 170,
            child: Row(
              children: [
                Switch(
                  value: f.enabled,
                  onChanged: _saving
                      ? null
                      : (v) => _setForward(
                          s,
                          cond,
                          PresenceForward(
                            enabled: v,
                            dest: f.dest.isEmpty ? 'ext_vm' : f.dest,
                            value: f.value,
                            number: f.number,
                            prefix: f.prefix,
                            callConfirm: f.callConfirm,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(color: f.enabled ? c.text : c.muted),
                  ),
                ),
              ],
            ),
          ),
          if (f.enabled) ...[
            choice<String>(
              tr('Destinazione'),
              f.dest,
              dests,
              (d) => _setForward(s, cond, to(d)),
              width: 200,
            ),
            if (f.dest == 'extension')
              choice<String>(
                tr('Interno'),
                f.value,
                {for (final e in dir) '${e.id}': '${e.number} ${e.name}'},
                (v) => _setForward(
                  s,
                  cond,
                  PresenceForward(
                    enabled: true,
                    dest: 'extension',
                    value: v,
                    prefix: f.prefix,
                  ),
                ),
                width: 220,
              ),
            if (f.dest == 'external_num')
              SizedBox(
                width: 200,
                child: TextFormField(
                  key: ValueKey('num-${s.status}-$cond'),
                  initialValue: f.number,
                  enabled: !_saving,
                  style: mono(c.text),
                  decoration: InputDecoration(labelText: tr('Numero')),
                  onChanged: (v) => _setForward(
                    s,
                    cond,
                    PresenceForward(
                      enabled: true,
                      dest: 'external_num',
                      number: v.trim(),
                      prefix: f.prefix,
                      callConfirm: f.callConfirm,
                    ),
                  ),
                ),
              ),
            if (f.dest == 'play_greeting')
              Text(f.value, style: mono(c.muted, size: 12)),
          ],
        ],
      ),
    );
  }

  Widget _forwards(
    DrinColors c,
    String title,
    String scope,
    PresenceSetting s,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
      ),
      const SizedBox(height: 4),
      _forward(c, s, '${scope}_always', tr('Sempre')),
      _forward(c, s, '${scope}_no_answer', tr('Nessuna risposta')),
      _forward(c, s, '${scope}_busy', tr('Occupato')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final d = detail;
    if (phone.primaryConnection == null) {
      return _Card(
        title: tr('Stato di presenza'),
        child: Text(
          tr('Non disponibile (collega il PBX)'),
          style: TextStyle(color: c.muted),
        ),
      );
    }
    final current = phone.ownDetail?.presence ?? phone.ownPresence;
    final viewed = _viewed ?? (current.isEmpty ? 'available' : current);
    final s = d?.settingOf(viewed);
    final viewedLabel = presenceOf(c, viewed)!.$3;
    final statusOptions = {
      for (final st in _statuses) st: presenceOf(c, st)!.$3,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        saveBar(c),
        _Card(
          title: tr('Stato di presenza'),
          action: IconButton(
            tooltip: tr('Rileggi dal PBX'),
            onPressed: _refreshing || _saving ? null : _refresh,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Field(
                    tr('Informazioni di presenza'),
                    d?.customPresence ?? '',
                    icon: Icons.chat_bubble_outline_rounded,
                  ),
                  if (phone.ownDetail != null && viewed != current)
                    FilledButton.tonalIcon(
                      onPressed: _saving || dirty
                          ? null
                          : () => save(phone.ownDetail!.withPresence(viewed)),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        tr('Imposta "{p}" come attuale', {'p': viewedLabel}),
                      ),
                    ),
                ],
              ),
              if (d == null) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Dettaglio non ancora letto dal PBX.'),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ],
          ),
        ),
        if (s != null) ...[
          _Card(
            title: tr('Inoltro di chiamata · {p}', {'p': viewedLabel}),
            child: AnimatedSectionSwitch(
              child: Column(
                key: ValueKey('fwd-$viewed'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _forwards(c, tr('Chiamate interne'), 'in', s),
                  const SizedBox(height: 14),
                  _forwards(c, tr('Chiamate esterne'), 'ex', s),
                ],
              ),
            ),
          ),
          _Card(
            title: tr('Squillo e cellulare · {p}', {'p': viewedLabel}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                choice<int>(
                  tr('Timeout squillo'),
                  s.ringTimeout ?? 30,
                  {
                    for (final t in {
                      10,
                      15,
                      20,
                      25,
                      30,
                      45,
                      60,
                      90,
                      120,
                      ?s.ringTimeout,
                    }.toList()..sort())
                      t: tr('{n} secondi', {'n': t}),
                  },
                  (t) => _setValues(s, {'ring_timeout': t}),
                  width: 200,
                ),
                const SizedBox(height: 6),
                toggle(
                  c,
                  tr('Squilla anche il cellulare'),
                  s.ringMobile,
                  (v) => _setValues(s, {'enb_ring_mobile': v ? 1 : 0}),
                  help: tr('Numero di cellulare dell\'interno sul PBX.'),
                ),
                if (s.ringMobile)
                  toggle(
                    c,
                    tr('Conferma con un tasto sul cellulare'),
                    s.mobileCallConfirm,
                    (v) => _setValues(s, {'mobile_call_confirm': v ? 1 : 0}),
                    help: tr(
                      'Evita che la chiamata finisca nella segreteria del '
                      'cellulare.',
                    ),
                  ),
                toggle(
                  c,
                  tr('Accetta chiamate dai gruppi di squillo'),
                  s.acceptRingGroup,
                  (v) => _setValues(s, {'enb_accept_call_from_rg': v ? 1 : 0}),
                ),
              ],
            ),
          ),
        ],
        if (d != null) ...[
          _Card(
            title: tr('Cambio automatico della presenza'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Il PBX cambia la presenza da solo secondo l\'orario '
                    'dell\'interno.',
                  ),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (key, label) in [
                      (
                        'presence_office_time_switch',
                        tr('In orario d\'ufficio'),
                      ),
                      ('presence_break_time_switch', tr('In pausa')),
                      ('presence_other_time_switch', tr('Fuori orario')),
                      ('presence_holiday_switch', tr('Nei giorni festivi')),
                    ])
                      choice<String>(
                        label,
                        d.field(key),
                        {'disable': tr('Non cambiare'), ...statusOptions},
                        (v) => edit(d.withValues({key: v})),
                        width: 220,
                      ),
                  ],
                ),
              ],
            ),
          ),
          _Card(
            title: tr('Più dispositivi'),
            child: Column(
              children: [
                toggle(
                  c,
                  tr('Occupato se un dispositivo è in chiamata'),
                  d.flag('enb_all_busy_mode_for_endpoints'),
                  (v) => edit(
                    d.withValues({
                      'enb_all_busy_mode_for_endpoints': v ? 1 : 0,
                    }),
                  ),
                  help: tr(
                    'Le nuove chiamate seguono l\'inoltro "Occupato" invece di '
                    'squillare sugli altri dispositivi.',
                  ),
                ),
                toggle(
                  c,
                  tr('Rifiuto su un dispositivo = rifiuto su tutti'),
                  d.flag('enb_all_reject_mode_for_endpoints'),
                  (v) => edit(
                    d.withValues({
                      'enb_all_reject_mode_for_endpoints': v ? 1 : 0,
                    }),
                  ),
                ),
              ],
            ),
          ),
          _ExtensionInfoCard(phone: phone),
        ],
      ],
    );
  }
}

// ---------------------------------------------- Casella vocale (sul PBX)

/// Impostazioni della casella sul PBX. Il PIN non si legge, non si mostra e
/// non si cambia: solo se è richiesto.
class _VoicemailPbxCard extends StatefulWidget {
  const _VoicemailPbxCard({required this.phone});
  final PhoneController phone;

  @override
  State<_VoicemailPbxCard> createState() => _VoicemailPbxCardState();
}

class _VoicemailPbxCardState extends State<_VoicemailPbxCard>
    with _OwnExtensionDraft<_VoicemailPbxCard> {
  @override
  PhoneController get phone => widget.phone;

  void _flag(String k, bool v) => edit(detail!.withValues({k: v ? 1 : 0}));

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final d = detail;
    if (d == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        saveBar(c),
        _Card(
          title: tr('Impostazioni sul PBX'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              toggle(
                c,
                tr('Casella vocale attiva'),
                d.flag('enb_vm'),
                (v) => _flag('enb_vm', v),
              ),
              toggle(
                c,
                tr('PIN richiesto per ascoltare'),
                d.flag('enb_vm_pin'),
                (v) => _flag('enb_vm_pin', v),
                help: tr('Il PIN si cambia dal PBX o da Linkus.'),
              ),
              toggle(
                c,
                tr('Annuncia data e ora del messaggio'),
                d.flag('enb_vm_play_datetime'),
                (v) => _flag('enb_vm_play_datetime', v),
              ),
              toggle(
                c,
                tr('Avviso via email dei nuovi messaggi'),
                d.flag('vm_new_email_notify'),
                (v) => _flag('vm_new_email_notify', v),
                help: tr('All\'indirizzo email dell\'interno sul PBX.'),
              ),
              if (d.flag('vm_new_email_notify'))
                toggle(
                  c,
                  tr('Allega l\'audio all\'email'),
                  d.flag('vm_email_with_audio'),
                  (v) => _flag('vm_email_with_audio', v),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  choice<String>(
                    tr('Dopo l\'avviso via email'),
                    d.field('vm_after_notification'),
                    {
                      'no': tr('Lascia da ascoltare'),
                      // Il PBX li accetta solo con l'audio allegato.
                      if (d.flag('vm_email_with_audio')) ...{
                        'mark_read': tr('Segna come ascoltato'),
                        'delete': tr('Elimina'),
                      },
                    },
                    (v) => edit(d.withValues({'vm_after_notification': v})),
                  ),
                  choice<String>(
                    tr('Formato dell\'ora'),
                    d.field('vm_play_time_format'),
                    {
                      'follow_system': tr('Come il sistema'),
                      '12-hour': tr('12 ore'),
                      '24-hour': tr('24 ore'),
                    },
                    (v) => edit(d.withValues({'vm_play_time_format': v})),
                  ),
                  _Field(tr('Messaggio di benvenuto'), switch (d.field(
                    'vm_greeting',
                  )) {
                    'follow_system' => tr('Come il sistema'),
                    'no_greeting' => tr('Nessuno'),
                    final g => g,
                  }, icon: Icons.record_voice_over_outlined),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------- Informazioni dell'interno

/// Dati dell'interno che gestisce l'amministratore: solo in lettura.
class _ExtensionInfoCard extends StatelessWidget {
  const _ExtensionInfoCard({required this.phone});
  final PhoneController phone;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final d = phone.ownDetail;
    if (d == null) return const SizedBox.shrink();
    String yes(String k) => d.flag(k) ? tr('Sì') : tr('No');
    final clients = [
      if (d.flag('enb_desktop_client')) 'Linkus Desktop',
      if (d.flag('enb_web_client')) 'Linkus Web',
      if (d.flag('enb_mobile_client')) 'Linkus Mobile',
    ];
    final fields = <(String, String, IconData)>[
      (
        tr('Nome'),
        '${d.field('first_name')} ${d.field('last_name')}'.trim(),
        Icons.badge_outlined,
      ),
      (tr('Email'), d.field('email_addr'), Icons.alternate_email_rounded),
      (tr('Cellulare'), d.field('mobile_number'), Icons.smartphone_rounded),
      (tr('ID chiamante'), d.field('caller_id'), Icons.call_made_rounded),
      (tr('Qualifica'), d.field('title'), Icons.work_outline_rounded),
      (
        tr('Registrazioni contemporanee'),
        d.field('concurrent_registrations'),
        Icons.devices_rounded,
      ),
      (tr('Trasporti SIP'), d.field('transport'), Icons.swap_horiz_rounded),
      (tr('SRTP'), yes('enb_srtp'), Icons.lock_outline_rounded),
      (
        tr('Chiamate in uscita bloccate'),
        yes('disable_outb_call'),
        Icons.block,
      ),
      (
        tr('Internazionali bloccate'),
        yes('disable_international_call'),
        Icons.public_off_rounded,
      ),
      (
        tr('Linkus abilitato'),
        clients.isEmpty ? '—' : clients.join(', '),
        Icons.apps_rounded,
      ),
    ];
    return _Card(
      title: tr('Informazioni dell\'interno'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final (label, value, icon) in fields)
                if (value.isNotEmpty) _Field(label, value, icon: icon),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr('Le gestisce l\'amministratore del PBX: qui solo in lettura.'),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}
