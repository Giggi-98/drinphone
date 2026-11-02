import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../shell/widgets.dart';

/// Casella vocale: messaggi dal PBX (API vm/get, o contatori SIP MWI) e ascolto
/// via codice funzione.
class VoicemailView extends StatelessWidget {
  const VoicemailView({super.key, required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget counter(String label, int n, Color color, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                Text(label, style: TextStyle(color: c.muted)),
              ],
            ),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Casella vocale'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              counter(
                tr('Nuovi messaggi'),
                phone.voicemailNew,
                phone.voicemailNew > 0 ? c.busy : c.muted,
                Icons.mark_email_unread_outlined,
              ),
              const SizedBox(width: 16),
              counter(
                tr('Già ascoltati'),
                phone.voicemailOld,
                c.muted,
                Icons.drafts_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.drin.free,
              foregroundColor: context.drin.onFree,
              minimumSize: const Size(240, 48),
            ),
            onPressed: phone.canDial ? phone.callVoicemail : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              tr('Ascolta messaggi ({code})', {
                'code': phone.settings.voicemailCode,
              }),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Messaggi letti dal PBX. L’ascolto chiama il codice della '
              'casella vocale, modificabile in Impostazioni.',
            ),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          if (phone.voicemailMessages != null) ...[
            const SizedBox(height: 20),
            Divider(color: c.border, height: 1),
            Expanded(
              child: phone.voicemailMessages!.isEmpty
                  ? Center(
                      child: Text(
                        tr('Nessun messaggio in casella.'),
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: phone.voicemailMessages!.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: c.border, height: 1),
                      itemBuilder: (_, i) {
                        final m = phone.voicemailMessages![i];
                        final who = m.callerName.isNotEmpty
                            ? m.callerName
                            : m.callerNumber;
                        return SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              Tooltip(
                                message: m.read ? tr('Ascoltato') : tr('Nuovo'),
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: m.read ? Colors.transparent : c.busy,
                                    border: Border.all(
                                      color: m.read ? c.border : c.busy,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      who,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: m.read
                                            ? FontWeight.w400
                                            : FontWeight.w700,
                                        color: c.text,
                                      ),
                                    ),
                                    if (m.callerName.isNotEmpty)
                                      Text(
                                        m.callerNumber,
                                        style: mono(c.muted, size: 12),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: Text(
                                  m.time,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  tr('{s} s', {'s': m.seconds}),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              CallIconButton(
                                tooltip: tr('Richiama {n}', {
                                  'n': m.callerNumber,
                                }),
                                onPressed:
                                    phone.canDial && m.callerNumber.isNotEmpty
                                    ? () => onCall(m.callerNumber)
                                    : null,
                              ),
                            ],
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
