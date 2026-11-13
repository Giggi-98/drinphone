import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/pbx/yeastar_api.dart';
import '../shell/widgets.dart';

/// Casella vocale: messaggi dal PBX (`vm/get`) con ascolto e scaricamento
/// in-app (`vm/download`), oppure chiamata al codice funzione della casella.
class VoicemailView extends StatefulWidget {
  const VoicemailView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  State<VoicemailView> createState() => _VoicemailViewState();
}

class _VoicemailViewState extends State<VoicemailView> {
  PhoneController get phone => widget.phone;

  Future<void> _saveVoicemail(PbxVoicemail m) async {
    final loc = await getSaveLocation(
      suggestedName: 'voicemail_${m.id}.wav',
      acceptedTypeGroups: [
        XTypeGroup(label: tr('Audio'), extensions: const ['wav', 'mp3']),
      ],
    );
    if (loc == null) return;
    try {
      await phone.downloadVoicemailAudio(m, targetFile: File(loc.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Messaggio vocale salvato'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is YeastarApiException ? '$e' : tr('Operazione non riuscita'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final hasPbx = phone.primaryConnection != null;

    Widget counter(String label, int n, Color color, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DrinSpace.s4,
          vertical: DrinSpace.s3,
        ),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(DrinRadius.panel),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: DrinSpace.s3),
            Text('$n', style: DrinText.numberLarge.copyWith(color: c.ink)),
            const SizedBox(width: DrinSpace.s3),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: DrinText.body.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.all(DrinSpace.s4),
      padding: const EdgeInsets.all(DrinSpace.s5),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(DrinRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tr('Casella vocale'),
                style: DrinText.title.copyWith(color: c.ink),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: phone.canDial ? phone.callVoicemail : null,
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text(
                  tr('Ascolta messaggi ({code})', {
                    'code': phone.settings.voicemailCode,
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: DrinSpace.s1),
          Text(
            tr(
              'Messaggi letti dal PBX. Puoi ascoltarli direttamente qui oppure '
              'chiamare la casella vocale.',
            ),
            style: DrinText.detail.copyWith(color: c.muted),
          ),
          const SizedBox(height: DrinSpace.s4),
          Row(
            children: [
              counter(
                tr('Nuovi messaggi'),
                phone.voicemailNew,
                phone.voicemailNew > 0 ? c.busy : c.muted,
                Icons.mark_email_unread_outlined,
              ),
              const SizedBox(width: DrinSpace.s4),
              counter(
                tr('Già ascoltati'),
                phone.voicemailOld,
                c.muted,
                Icons.drafts_outlined,
              ),
            ],
          ),
          ListenableBuilder(
            listenable: phone.mediaPlayer,
            builder: (_, _) {
              final err = phone.mediaPlayer.error;
              if (err == null || err.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: DrinSpace.s3),
                child: Text(
                  tr('Riproduzione non riuscita: {e}', {'e': err}),
                  style: DrinText.detail.copyWith(color: c.busyText),
                ),
              );
            },
          ),
          if (phone.voicemailMessages != null) ...[
            const SizedBox(height: DrinSpace.s4),
            Divider(color: c.line, height: 1),
            Expanded(
              child: phone.voicemailMessages!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.voicemail_rounded,
                            size: 40,
                            color: c.muted,
                          ),
                          const SizedBox(height: DrinSpace.s3),
                          Text(
                            tr('Nessun messaggio in casella.'),
                            style: DrinText.heading.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: phone.voicemailMessages!.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: c.line, height: 1),
                      itemBuilder: (_, i) {
                        final m = phone.voicemailMessages![i];
                        final who = m.callerName.isNotEmpty
                            ? m.callerName
                            : m.callerNumber;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: DrinSpace.s2,
                          ),
                          child: ListenableBuilder(
                            listenable: phone.mediaPlayer,
                            builder: (_, _) {
                              final trackKey = 'vm:${m.id}';
                              final active = phone.mediaPlayer.isActive(
                                trackKey,
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Tooltip(
                                        message: m.read
                                            ? tr('Ascoltato')
                                            : tr('Nuovo'),
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: m.read
                                                ? Colors.transparent
                                                : c.busy,
                                            border: Border.all(
                                              color: m.read ? c.line : c.busy,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: DrinSpace.s3),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              who,
                                              overflow: TextOverflow.ellipsis,
                                              style: DrinText.body.copyWith(
                                                fontWeight: m.read
                                                    ? FontWeight.w400
                                                    : FontWeight.w700,
                                                color: c.ink,
                                              ),
                                            ),
                                            if (m.callerName.isNotEmpty)
                                              Text(
                                                m.callerNumber,
                                                overflow: TextOverflow.ellipsis,
                                                style: DrinText.number.copyWith(
                                                  fontSize: 12,
                                                  color: c.muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: DrinSpace.s2),
                                      SizedBox(
                                        width: 150,
                                        child: Text(
                                          m.time,
                                          overflow: TextOverflow.ellipsis,
                                          style: DrinText.number.copyWith(
                                            fontSize: 12.5,
                                            color: c.muted,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 56,
                                        child: Text(
                                          tr('{s} s', {'s': m.seconds}),
                                          style: DrinText.number.copyWith(
                                            fontSize: 12.5,
                                            color: c.muted,
                                          ),
                                        ),
                                      ),
                                      if (hasPbx && !active) ...[
                                        InlineAudioPlayerBar(
                                          player: phone.mediaPlayer,
                                          trackKey: trackKey,
                                          fallbackDurationSec: m.seconds,
                                          compact: true,
                                          resolveFile: () async =>
                                              (await phone
                                                      .downloadVoicemailAudio(
                                                        m,
                                                      ))
                                                  .$2,
                                          onDownload: () => _saveVoicemail(m),
                                        ),
                                        const SizedBox(width: DrinSpace.s1),
                                      ],
                                      CallIconButton(
                                        tooltip: tr('Richiama {n}', {
                                          'n': m.callerNumber,
                                        }),
                                        onPressed:
                                            phone.canDial &&
                                                m.callerNumber.isNotEmpty
                                            ? () => widget.onCall(
                                                m.callerNumber,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                  if (hasPbx && active) ...[
                                    const SizedBox(height: DrinSpace.s2),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: DrinSpace.s4,
                                      ),
                                      child: InlineAudioPlayerBar(
                                        player: phone.mediaPlayer,
                                        trackKey: trackKey,
                                        fallbackDurationSec: m.seconds,
                                        compact: false,
                                        resolveFile: () async =>
                                            (await phone.downloadVoicemailAudio(
                                              m,
                                            )).$2,
                                        onDownload: () => _saveVoicemail(m),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
