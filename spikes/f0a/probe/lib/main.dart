// F0-A probe: proves that liblinphone can be initialised from Flutter, emits
// events back to Dart and accepts API calls. NOT product code.
//
// The REGISTER target is a closed local port on purpose: no PBX exists yet
// (F1), so the expected result is Progress -> Failed. That exercises the event
// path only; it is not evidence of a working SIP registration.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'engine.dart';

const _probeDomain = '127.0.0.1:5999';

void main() {
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  final _lines = <String>[];
  final ProbeEngine _engine = ProbeEngine.forPlatform();
  StreamSubscription<String>? _sub;

  void _log(String line) {
    // Single greppable prefix so the runner script can assert on stdout/logcat.
    // ignore: avoid_print
    print('F0A $line');
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      _sub = _engine.events.listen((e) => _log('EVENT $e'));
      _log('INIT version=${await _engine.init()}');
      await _engine.register('f0a-probe', _probeDomain);
      _log('REGISTER_REQUESTED domain=$_probeDomain');
      await Future<void>.delayed(const Duration(seconds: 12));
      await _engine.destroy();
      _log('DESTROYED');
      _log('DONE');
    } catch (e) {
      _log('ERROR $e');
    } finally {
      await _sub?.cancel();
      if (Platform.isLinux || Platform.isWindows) exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('DrinPhone F0-A probe')),
        body: ListView(children: [for (final l in _lines) Text(l)]),
      ),
    );
  }
}
