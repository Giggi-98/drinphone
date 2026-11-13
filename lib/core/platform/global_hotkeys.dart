import 'dart:io';

import 'package:flutter/services.dart';

import '../../app/phone_controller.dart';
import '../sip/sip_engine.dart';
import 'call_links.dart';

/// Scorciatoie globali opzionali su Windows (`RegisterHotKey` nel runner Win32).
class GlobalHotkeys {
  GlobalHotkeys._();
  static final instance = GlobalHotkeys._();

  static const channel = MethodChannel('drinphone/hotkeys');

  static const labels = [
    ('Ctrl + Alt + A', 'Rispondi / termina chiamata'),
    ('Ctrl + Alt + M', 'Microfono muto / attivo'),
    ('Ctrl + Alt + D', 'Chiama numero negli appunti'),
  ];

  /// Estrae un numero telefonico pulito dagli appunti (o da un link `tel:`/`sip:`),
  /// altrimenti `null` se il testo non sembra un numero valido.
  static String? sanitizeClipboardNumber(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final fromLink = numberFromLink(trimmed);
    if (fromLink != null) return fromLink;
    final stripped = trimmed.replaceAll(RegExp(r'[\s\-.()/]'), '');
    if (stripped.length < 2 ||
        stripped.length > 32 ||
        !RegExp(r'^\+?[0-9]+$').hasMatch(stripped)) {
      return null;
    }
    return stripped;
  }

  /// Attiva o disattiva le scorciatoie globali su Windows.
  Future<Map<String, bool>> apply(bool enabled) async {
    if (!Platform.isWindows) return const {};
    try {
      final res = await channel.invokeMapMethod<String, bool>(
        'setEnabled',
        enabled,
      );
      return res ?? const {};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  void listen(void Function(String action) onAction) {
    channel.setMethodCallHandler((call) async {
      final action = call.arguments;
      if (call.method == 'triggered' && action is String) {
        onAction(action);
      }
    });
  }

  void unlisten() {
    channel.setMethodCallHandler(null);
  }

  /// Esegue l'azione di una scorciatoia globale sul [phone].
  static Future<void> handleAction(
    String action,
    PhoneController phone, {
    Future<String?> Function()? readClipboard,
    void Function(String number)? onDialCandidate,
    void Function()? onShowWindow,
  }) async {
    if (!phone.loggedIn) return;
    switch (action) {
      case 'answerHangup':
        final incoming = phone.calls.values
            .where((c) => c.phase == CallPhase.incoming)
            .firstOrNull;
        if (incoming != null) {
          onShowWindow?.call();
          await phone.answer(incoming.id);
        } else if (phone.call != null) {
          await phone.hangup();
        }
      case 'mute':
        if (phone.call != null) {
          await phone.toggleMute();
        }
      case 'dialClipboard':
        final raw =
            await (readClipboard ??
                () async =>
                    (await Clipboard.getData(Clipboard.kTextPlain))?.text)();
        final number = sanitizeClipboardNumber(raw);
        if (number != null) {
          onShowWindow?.call();
          (onDialCandidate ?? (n) => pendingCallLink.value = n)(number);
        }
    }
  }
}

