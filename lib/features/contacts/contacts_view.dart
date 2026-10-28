import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../shell/widgets.dart';

/// Rubrica aziendale letta dai PBX (sola lettura), filtrabile e a pagine.
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

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final all = p.contactsMatching(_filter.text);
    final books = {for (final x in all) ...x.$2.phonebooks}.toList()..sort();
    final list = [
      for (final x in all)
        if (_book == null || x.$2.phonebooks.contains(_book)) x,
    ];
    final pages = (list.length + pageSize - 1) ~/ pageSize;
    if (_page >= pages && pages > 0) _page = pages - 1;
    final slice = Pager.slice(list, _page, pageSize);
    final multi = p.connections.length > 1;

    Widget chip(String label, String? value) {
      final on = _book == value;
      return Material(
        color: on ? c.keyBtn : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.accent : c.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() {
            _book = value;
            _page = 0;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: on ? c.accent : c.text),
            ),
          ),
        ),
      );
    }

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
                tr('Rubrica aziendale'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 12),
              CountBadge(list.length),
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
              const SizedBox(width: 10),
              Tooltip(
                message: tr('Sola lettura dal PBX'),
                child: Icon(Icons.lock_outline, size: 16, color: c.muted),
              ),
            ],
          ),
          if (books.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                chip(tr('Tutte'), null),
                for (final b in books) chip(b, b),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      p.connections.isEmpty
                          ? tr(
                              'Collega un PBX in Integrazione PBX per vedere la rubrica.',
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
                      final (conn, x) = slice[i];
                      final sub = [
                        if (x.company.isNotEmpty) x.company,
                        if (x.jobTitle.isNotEmpty) x.jobTitle,
                        if (multi) conn.label,
                      ].join(' · ');
                      return SizedBox(
                        height: 58,
                        child: Row(
                          children: [
                            StatusAvatar(name: x.name, size: 34),
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
