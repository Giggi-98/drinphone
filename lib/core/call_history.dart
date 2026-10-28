import 'dart:convert';
import 'dart:io';

import 'sip/sip_engine.dart';

class CallRecord {
  const CallRecord({
    required this.number,
    required this.name,
    required this.direction,
    required this.start,
    required this.seconds,
    required this.answered,
  });

  final String number;
  final String name;
  final CallDirection direction;
  final DateTime start;

  /// Durata della conversazione (0 se non risposta).
  final int seconds;
  final bool answered;

  bool get missed => direction == CallDirection.incoming && !answered;

  Map<String, Object> toJson() => {
    'number': number,
    'name': name,
    'direction': direction.name,
    'start': start.toIso8601String(),
    'seconds': seconds,
    'answered': answered,
  };

  static CallRecord fromJson(Map<String, dynamic> j) => CallRecord(
    number: j['number'] as String? ?? '',
    name: j['name'] as String? ?? '',
    direction: CallDirection.values.byName(j['direction'] as String),
    start: DateTime.parse(j['start'] as String),
    seconds: j['seconds'] as int? ?? 0,
    answered: j['answered'] as bool? ?? false,
  );
}

/// Cronologia locale (dati personali: solo su questo PC, nella cartella dell'app).
class CallHistoryStore {
  CallHistoryStore(this.path);
  final String path;
  static const maxRecords = 200;

  Future<List<CallRecord>> load() async {
    final f = File(path);
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return [
        for (final j in list) CallRecord.fromJson(j as Map<String, dynamic>),
      ];
    } on FormatException {
      return [];
    }
  }

  /// Più recenti per prime.
  Future<void> save(List<CallRecord> records) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode([for (final r in records.take(maxRecords)) r.toJson()]),
    );
  }

  Future<void> clear() async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
