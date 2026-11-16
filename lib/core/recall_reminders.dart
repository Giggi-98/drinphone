import 'dart:convert';
import 'dart:io';

/// Promemoria di richiamata pianificato dall'utente su un numero (solo locale).
class RecallReminder {
  const RecallReminder({
    required this.id,
    required this.profileId,
    required this.number,
    required this.name,
    required this.dueAt,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String profileId;
  final String number;
  final String name;
  final String note;
  final DateTime dueAt;
  final DateTime createdAt;

  RecallReminder postpone(Duration by, {DateTime? now}) {
    final base = now ?? DateTime.now();
    return RecallReminder(
      id: id,
      profileId: profileId,
      number: number,
      name: name,
      note: note,
      dueAt: base.add(by),
      createdAt: createdAt,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'profileId': profileId,
    'number': number,
    'name': name,
    'dueAt': dueAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    if (note.isNotEmpty) 'note': note,
  };

  static RecallReminder? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final number = j['number'] as String? ?? '';
    final dueRaw = j['dueAt'] as String? ?? '';
    final createdRaw = j['createdAt'] as String? ?? '';
    final dueAt = DateTime.tryParse(dueRaw);
    if (id.isEmpty || number.isEmpty || dueAt == null) return null;
    return RecallReminder(
      id: id,
      profileId: j['profileId'] as String? ?? 'default',
      number: number,
      name: j['name'] as String? ?? '',
      note: j['note'] as String? ?? '',
      dueAt: dueAt,
      createdAt: DateTime.tryParse(createdRaw) ?? dueAt,
    );
  }

  /// Prossimo giorno lavorativo alle 09:00 locali (se già dopo le 09:00 o weekend).
  static DateTime nextMorning(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, 9, 0);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d;
  }
}

/// Archivio JSON locale dei promemoria di richiamata.
class RecallReminderStore {
  RecallReminderStore(this.path);
  final String path;
  static const maxItems = 100;

  Future<void> _queue = Future.value();

  Future<List<RecallReminder>> load() async {
    final f = File(path);
    if (!await f.exists()) return [];
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map<String, dynamic>)
            ?RecallReminder.fromJson(item),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<RecallReminder> items) {
    final next = _queue.then((_) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode([for (final r in items.take(maxItems)) r.toJson()]),
      );
    });
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }
}

