import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/update/updater.dart';
import '../shell/desktop_shell.dart';
import 'release_notes_dialog.dart';

/// Stato degli aggiornamenti, "Verifica ora" e "Installa e riavvia"
/// (Preferenze > Diagnostica e finestra dalla barra laterale).
class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.phone, required this.updater});
  final PhoneController phone;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final u = updater;
        final next = u.available;
        final busy = u.progress != null;
        final last = u.lastCheck;
        final status = u.checking
            ? tr('Verifica in corso…')
            : u.error != null
            ? tr('Aggiornamento non riuscito: {e}', {'e': u.error!})
            : next != null
            ? tr('Disponibile la versione {v}', {'v': next.version})
            : last != null
            ? tr('Nessun aggiornamento (controllo delle {t})', {
                't':
                    '${last.hour.toString().padLeft(2, '0')}:'
                    '${last.minute.toString().padLeft(2, '0')}',
              })
            : u.isDevBuild
            ? tr('Build di sviluppo: nessun controllo automatico')
            : tr('Controllo automatico ogni 6 ore');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Versione installata: {v}', {'v': u.current}),
              style: TextStyle(color: c.text),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: u.error != null ? c.busyText : c.muted,
              ),
            ),
            if (busy) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 320,
                child: LinearProgressIndicator(value: u.progress),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: u.checking || busy ? null : u.check,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(tr('Verifica ora')),
                ),
                if (next != null && !next.releaseNotes.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => showReleaseNotes(
                      context,
                      next.releaseNotes,
                      title: tr('Cosa cambia nella {v}', {'v': next.version}),
                    ),
                    icon: const Icon(Icons.celebration_rounded, size: 18),
                    label: Text(tr('Cosa cambia')),
                  ),
                if (next != null)
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            if (phone.call != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr('Non durante una chiamata')),
                                ),
                              );
                              return;
                            }
                            u.install(() async {
                              await phone.shutdown();
                              await DesktopShell.instance?.dispose();
                            });
                          },
                    icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                    label: Text(tr('Installa e riavvia')),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

Future<void> showUpdateDialog(
  BuildContext context,
  PhoneController phone,
  Updater updater,
) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(tr('Aggiornamento')),
    content: SizedBox(
      width: 420,
      child: UpdatePanel(phone: phone, updater: updater),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text(tr('Più tardi')),
      ),
    ],
  ),
);
