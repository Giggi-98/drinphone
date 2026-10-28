import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';

/// Rubrica aziendale letta dai PBX (sola lettura).
class ContactsView extends StatefulWidget {
  const ContactsView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  /// Rubrica (phonebook) selezionata; null = tutte.
  String? _book;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final p = widget.phone;
    final all = p.visibleContacts;
    final books = {for (final x in all) ...x.$2.phonebooks}.toList()..sort();
    final list = [
      for (final x in all)
        if (_book == null || x.$2.phonebooks.contains(_book)) x,
    ];
    final multi = p.connections.length > 1;

    Widget chip(String label, String? value) {
      final on = _book == value;
      return Material(
        color: on ? c.keyBtn : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.accent : c.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _book = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: on ? c.accent : c.text),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                p.query.isEmpty
                    ? 'Rubrica aziendale'
                    : 'Rubrica · «${p.query}»',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${list.length} contatti',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const Spacer(),
              Icon(Icons.lock_outline, size: 14, color: c.muted),
              const SizedBox(width: 6),
              Text(
                'Sola lettura dal PBX',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
          if (books.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                chip('Tutte', null),
                for (final b in books) chip(b, b),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      p.connections.isEmpty
                          ? 'Collega un PBX in Integrazione PBX per vedere la rubrica.'
                          : 'Nessun contatto.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: c.border, height: 1),
                    itemBuilder: (_, i) {
                      final (conn, x) = list[i];
                      final initials = x.name
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .map((w) => w[0])
                          .take(2)
                          .join()
                          .toUpperCase();
                      final sub = [
                        if (x.company.isNotEmpty) x.company,
                        if (x.jobTitle.isNotEmpty) x.jobTitle,
                        if (multi) conn.label,
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: c.avatar,
                              child: Text(
                                initials,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 260,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    x.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
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
                                  if (x.email.isNotEmpty)
                                    Text(
                                      x.email,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final (label, number) in x.numbers)
                                    OutlinedButton.icon(
                                      onPressed: p.canDial
                                          ? () => widget.onCall(number)
                                          : null,
                                      icon: Icon(
                                        Icons.call,
                                        size: 14,
                                        color: c.accent,
                                      ),
                                      label: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '$label  ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: c.muted,
                                              ),
                                            ),
                                            TextSpan(
                                              text: number,
                                              style: TextStyle(
                                                fontFamily: monoFont,
                                                color: c.text,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
