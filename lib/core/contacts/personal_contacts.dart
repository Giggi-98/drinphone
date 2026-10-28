import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Contatto personale dell'utente, legato al profilo (DECISIONS "Profili").
class PersonalContact {
  const PersonalContact({
    required this.id,
    required this.name,
    this.company = '',
    this.email = '',
    this.numbers = const [],
  });
  final String id;
  final String name;
  final String company;
  final String email;

  /// (etichetta, numero): `Cellulare`, `Ufficio`, `Casa`, `Altro`.
  final List<(String, String)> numbers;

  static const labels = ['Cellulare', 'Ufficio', 'Casa', 'Altro'];

  static String newId() => List.generate(
    12,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'email': email,
    'numbers': [
      for (final (l, n) in numbers) {'label': l, 'number': n},
    ],
  };

  static PersonalContact fromJson(Map<String, dynamic> j) => PersonalContact(
    id: '${j['id'] ?? newId()}',
    name: '${j['name'] ?? ''}',
    company: '${j['company'] ?? ''}',
    email: '${j['email'] ?? ''}',
    numbers: [
      for (final n in (j['numbers'] as List? ?? const []))
        if (n is Map) ('${n['label'] ?? 'Altro'}', '${n['number'] ?? ''}'),
    ],
  );
}

/// Contatti personali in JSON nella cartella dell'app (come il registro
/// chiamate: protetti dall'account Windows, non cifrati).
class PersonalContactsStore {
  PersonalContactsStore(this.path);
  final String path;

  Future<List<PersonalContact>> load() async {
    final f = File(path);
    if (!await f.exists()) return [];
    try {
      return [
        for (final j in jsonDecode(await f.readAsString()) as List)
          PersonalContact.fromJson(j as Map<String, dynamic>),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<PersonalContact> list) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode([for (final c in list) c.toJson()]));
  }
}

/// Lettura di contatti da file CSV o vCard. Scarta i contatti senza numero
/// e i fax.
class ContactImport {
  /// Formato dal nome del file e dal contenuto.
  static List<PersonalContact> parse(String fileName, String text) {
    final body = text.startsWith('﻿') ? text.substring(1) : text;
    final vcf =
        fileName.toLowerCase().endsWith('.vcf') ||
        body.trimLeft().toUpperCase().startsWith('BEGIN:VCARD');
    return (vcf ? vcard(body) : csv(body))
        .where((c) => c.numbers.isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------------------ vCard

  static List<PersonalContact> vcard(String text) {
    // Righe piegate (RFC 6350 §3.2): continuano con spazio o tab.
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n[ \t]'), '')
        .split('\n');
    final out = <PersonalContact>[];
    String fn = '', n = '', org = '', email = '';
    var numbers = <(String, String)>[];
    for (final raw in lines) {
      final i = raw.indexOf(':');
      if (i < 0) continue;
      final head = raw.substring(0, i).toUpperCase();
      final value = raw.substring(i + 1).trim();
      final prop = head.split(';').first.split('.').last;
      switch (prop) {
        case 'BEGIN':
          fn = n = org = email = '';
          numbers = [];
        case 'FN':
          fn = _unescape(value);
        case 'N':
          // Cognome;Nome;Altri;Prefisso;Suffisso
          final p = value.split(';').map(_unescape).toList();
          n = [
            if (p.length > 1) p[1],
            p[0],
          ].where((x) => x.isNotEmpty).join(' ');
        case 'ORG':
          org = _unescape(value.split(';').first);
        case 'EMAIL':
          if (email.isEmpty) email = value;
        case 'TEL':
          if (head.contains('FAX')) break;
          final number = value.replaceFirst(
            RegExp(r'^tel:', caseSensitive: false),
            '',
          );
          if (number.isEmpty) break;
          numbers.add((
            head.contains('CELL')
                ? 'Cellulare'
                : head.contains('WORK')
                ? 'Ufficio'
                : head.contains('HOME')
                ? 'Casa'
                : 'Altro',
            number,
          ));
        case 'END':
          final name = fn.isNotEmpty ? fn : (n.isNotEmpty ? n : org);
          if (name.isNotEmpty || numbers.isNotEmpty) {
            out.add(
              PersonalContact(
                id: PersonalContact.newId(),
                name: name.isNotEmpty ? name : numbers.first.$2,
                company: org,
                email: email,
                numbers: numbers,
              ),
            );
          }
      }
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\\', r'\')
      .trim();

  // -------------------------------------------------------------------- CSV

  static List<PersonalContact> csv(String text) {
    final firstLine = text.split('\n').first;
    // Excel italiano usa il punto e virgola.
    final sep =
        ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
        ? ';'
        : ',';
    final rows = _rows(text, sep);
    if (rows.length < 2) return [];
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    int col(List<String> keys, {List<String> not = const []}) =>
        header.indexWhere((h) => keys.any(h.contains) && !not.any(h.contains));
    final full = col(['display name', 'nome completo', 'full name']);
    final first = col(
      ['first name', 'given name', 'nome'],
      not: [
        'cognome',
        'completo',
        'display',
        'full',
        'azienda',
        'company',
        'utente',
      ],
    );
    final last = col(['last name', 'family name', 'surname', 'cognome']);
    final plain = col(
      ['name'],
      not: [
        'first',
        'last',
        'given',
        'family',
        'company',
        'display',
        'full',
        'user',
      ],
    );
    final company = col([
      'company',
      'organization',
      'organisation',
      'azienda',
      'società',
      'ditta',
    ]);
    final email = col(['e-mail', 'email', 'mail']);
    final phones = [
      for (var i = 0; i < header.length; i++)
        if (RegExp(r'phone|tel|mobile|cell|numero|fisso|pager')
                .hasMatch(header[i]) &&
            // Google: "Phone 1 - Type" contiene l'etichetta, non il numero.
            !RegExp(r'fax|type|tipo|label|etichetta').hasMatch(header[i]))
          i,
    ];
    String at(List<String> r, int i) =>
        i >= 0 && i < r.length ? r[i].trim() : '';
    String labelOf(String h) => RegExp(r'mobile|cell').hasMatch(h)
        ? 'Cellulare'
        : RegExp(r'business|work|office|ufficio|lavoro|aziend').hasMatch(h)
        ? 'Ufficio'
        : RegExp(r'home|casa|abitazione').hasMatch(h)
        ? 'Casa'
        : 'Altro';
    return [
      for (final r in rows.skip(1))
        if (r.any((x) => x.trim().isNotEmpty))
          () {
            final numbers = [
              for (final i in phones)
                if (at(r, i).isNotEmpty) (labelOf(header[i]), at(r, i)),
            ];
            final composed = [
              at(r, first),
              at(r, last),
            ].where((x) => x.isNotEmpty).join(' ');
            var name = at(r, full);
            if (name.isEmpty) name = composed;
            if (name.isEmpty) name = at(r, plain);
            if (name.isEmpty) name = at(r, company);
            if (name.isEmpty && numbers.isNotEmpty) name = numbers.first.$2;
            return PersonalContact(
              id: PersonalContact.newId(),
              name: name,
              company: at(r, company),
              email: at(r, email),
              numbers: numbers,
            );
          }(),
    ];
  }

  /// Righe CSV con campi tra virgolette (anche a capo dentro e `""`).
  static List<List<String>> _rows(String text, String sep) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == sep) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
