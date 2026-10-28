import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/contacts/personal_contacts.dart';
import '../shell/widgets.dart';

/// Rubrica: contatti personali del profilo (modificabili, importabili da CSV
/// o vCard) e rubrica aziendale dei PBX (sola lettura), filtrabile e a pagine.
class ContactsView extends StatefulWidget {
  const ContactsView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final _filter = TextEditingController();

  /// Rubrica (phonebook) selezionata; null = tutte.
  String? _book;
  int _page = 0;
  static const pageSize = 50;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  static IconData _iconFor(String label) => label.startsWith(tr('Cellulare'))
      ? Icons.smartphone_rounded
      : label.startsWith(tr('Casa'))
      ? Icons.home_outlined
      : label.startsWith(tr('Ufficio'))
      ? Icons.business_rounded
      : Icons.call_rounded;

  Future<void> _edit(BuildContext context, [PersonalContact? contact]) =>
      showDialog<void>(
        context: context,
        builder: (_) => _ContactDialog(phone: widget.phone, contact: contact),
      );

  Future<void> _delete(BuildContext context, PersonalContact contact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminare {n}?', {'n': contact.name})),
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
    if (ok == true) await widget.phone.deletePersonal(contact.id);
  }

  /// Importazione: scelta del file, anteprima con i doppioni, conferma.
  Future<void> _import(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('Contatti'), extensions: const ['csv', 'vcf']),
      ],
    );
    if (file == null || !context.mounted) return;
    List<PersonalContact> found;
    try {
      found = ContactImport.parse(file.name, await file.readAsString());
    } on FormatException {
      found = const [];
    }
    if (!context.mounted) return;
    final dup = found.where(widget.phone.isPersonalDuplicate).length;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Importa contatti')),
        content: Text(
          found.isEmpty
              ? tr('Nessun contatto con numero di telefono in {f}.', {
                  'f': file.name,
                })
              : tr(
                  '{n} contatti in {f}, di cui {d} già presenti (stesso numero).',
                  {'n': found.length, 'f': file.name, 'd': dup},
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Annulla')),
          ),
          if (found.isNotEmpty && dup > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Importa tutti')),
            ),
          if (found.length > dup)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dup > 0 ? tr('Importa i nuovi') : tr('Importa')),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final n = await widget.phone.importPersonal(found, skipDuplicates: choice);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('{n} contatti importati', {'n': n}))),
    );
    setState(() {
      _book = PhoneController.personalBook;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final all = p.contactsMatching(_filter.text);
    final books = {
      for (final x in all)
        if (x.$3 == null) ...x.$2.phonebooks,
    }.toList()..sort();
    final hasPersonal = p.personal.isNotEmpty;
    final list = [
      for (final x in all)
        if (_book == null || x.$2.phonebooks.contains(_book)) x,
    ];
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
    final multi = p.connections.length > 1;

    return Container(
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
              Text(
                tr('Rubrica'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 12),
              CountBadge(list.length),
              // Personali e rubriche del PBX come menu a tendina (stile Linkus).
              if (books.length + (hasPersonal ? 1 : 0) > 1) ...[
                const SizedBox(width: 16),
                Icon(Icons.menu_book_outlined, size: 18, color: c.muted),
                const SizedBox(width: 6),
                DropdownButton<String?>(
                  value:
                      books.contains(_book) ||
                          _book == PhoneController.personalBook
                      ? _book
                      : null,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr('Tutte le rubriche')),
                    ),
                    if (hasPersonal)
                      DropdownMenuItem(
                        value: PhoneController.personalBook,
                        child: Text(tr('Contatti personali')),
                      ),
                    for (final b in books)
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) => setState(() {
                    _book = v;
                    _page = 0;
                  }),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() => _page = 0),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                    hintText: tr('Filtra per nome, azienda o numero'),
                    hintStyle: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr('Importa contatti (CSV, vCard)'),
                onPressed: () => _import(context),
                icon: Icon(Icons.upload_file_rounded, color: c.muted),
              ),
              IconButton.filledTonal(
                tooltip: tr('Nuovo contatto'),
                style: IconButton.styleFrom(
                  backgroundColor: c.keyBtn,
                  foregroundColor: c.accent,
                ),
                onPressed: () => _edit(context),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _filter.text.isEmpty && all.isEmpty
                          ? tr(
                              'Nessun contatto. Aggiungine uno con + o importali da CSV o vCard.',
                            )
                          : tr('Nessun contatto.'),
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: slice.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.border, height: 1),
                    itemBuilder: (_, i) {
                      final (conn, x, own) = slice[i];
                      final sub = [
                        if (x.company.isNotEmpty) x.company,
                        if (x.jobTitle.isNotEmpty) x.jobTitle,
                        if (own != null &&
                            x.company.isEmpty &&
                            x.email.isNotEmpty)
                          x.email,
                        if (multi && conn != null) conn.label,
                      ].join(' · ');
                      return SizedBox(
                        height: 58,
                        child: Row(
                          children: [
                            StatusAvatar(name: x.name, size: 34),
                            if (own != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Tooltip(
                                  message: tr('Contatto personale'),
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    size: 14,
                                    color: c.accent,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    x.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: c.text,
                                    ),
                                  ),
                                  if (sub.isNotEmpty)
                                    Text(
                                      sub,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            for (final (label, number) in x.numbers)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Tooltip(
                                  message: '${tr(label)} · $number',
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(color: c.border),
                                    ),
                                    onPressed: p.canDial
                                        ? () => widget.onCall(number)
                                        : null,
                                    icon: Icon(
                                      _iconFor(tr(label)),
                                      size: 16,
                                      color: c.accent,
                                    ),
                                    label: Text(
                                      number,
                                      style: mono(c.text, size: 12),
                                    ),
                                  ),
                                ),
                              ),
                            if (own != null)
                              PopupMenuButton<String>(
                                tooltip: '',
                                icon: Icon(Icons.more_vert, color: c.muted),
                                onSelected: (v) => v == 'edit'
                                    ? _edit(context, own)
                                    : _delete(context, own),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(tr('Modifica')),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(tr('Elimina')),
                                  ),
                                ],
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Tooltip(
                                  message: tr('Sola lettura dal PBX'),
                                  child: Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
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
        ],
      ),
    );
  }
}

/// Nuovo contatto personale o modifica: nome, azienda, email, numeri.
class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.phone, this.contact});
  final PhoneController phone;
  final PersonalContact? contact;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final _name = TextEditingController(text: widget.contact?.name);
  late final _company = TextEditingController(text: widget.contact?.company);
  late final _email = TextEditingController(text: widget.contact?.email);
  late final _numbers = [
    for (final (l, n) in widget.contact?.numbers ?? const [('Cellulare', '')])
      (l, TextEditingController(text: n)),
  ];

  @override
  void dispose() {
    for (final t in [_name, _company, _email, for (final n in _numbers) n.$2]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final numbers = [
      for (final (l, t) in _numbers)
        if (t.text.trim().isNotEmpty) (l, t.text.trim()),
    ];
    final name = _name.text.trim();
    if (name.isEmpty || numbers.isEmpty) return;
    await widget.phone.savePersonal(
      PersonalContact(
        id: widget.contact?.id ?? PersonalContact.newId(),
        name: name,
        company: _company.text.trim(),
        email: _email.text.trim(),
        numbers: numbers,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return AlertDialog(
      title: Text(
        widget.contact == null ? tr('Nuovo contatto') : tr('Modifica contatto'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Nome')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _company,
                decoration: InputDecoration(labelText: tr('Azienda')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                decoration: InputDecoration(labelText: tr('Email')),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < _numbers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      DropdownButton<String>(
                        value: _numbers[i].$1,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final l in PersonalContact.labels)
                            DropdownMenuItem(value: l, child: Text(tr(l))),
                        ],
                        onChanged: (v) => setState(
                          () => _numbers[i] = (v ?? 'Altro', _numbers[i].$2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _numbers[i].$2,
                          style: mono(c.text),
                          decoration: InputDecoration(hintText: tr('Numero')),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Rimuovi'),
                        onPressed: _numbers.length < 2
                            ? null
                            : () => setState(() {
                                _numbers.removeAt(i).$2.dispose();
                              }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _numbers.add(('Ufficio', TextEditingController())),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(tr('Aggiungi numero')),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annulla')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Salva'))),
      ],
    );
  }
}
