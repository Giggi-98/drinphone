import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/profile_bundle.dart';

/// Esporta il profilo attivo in un file cifrato `.drinprof`.
Future<void> showExportProfileDialog(
  BuildContext context,
  PhoneController phone,
) async {
  final rawName = phone.settings.profileName.trim().isNotEmpty
      ? phone.settings.profileName.trim()
      : (phone.settings.account?.username ?? 'drinphone');
  final safeName = rawName.replaceAll(RegExp(r'[^0-9A-Za-z._-]+'), '_');
  final pass1 = TextEditingController();
  final pass2 = TextEditingController();
  var includeSip = true;
  var includePbx = true;
  var includeContacts = true;
  String? err;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.drin;
        return AlertDialog(
          title: Text(tr('Esporta profilo (.drinprof)')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Il file viene cifrato (AES-256-GCM) con la passphrase scelta qui sotto.',
                    ),
                    style: DrinText.body.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: DrinSpace.s3),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeSip,
                    onChanged: (v) => setState(() => includeSip = v ?? true),
                    title: Text(tr('Includi password account SIP')),
                  ),
                  if (phone.isYeastar)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includePbx,
                      onChanged: (v) => setState(() => includePbx = v ?? true),
                      title: Text(tr('Includi credenziali PBX API e CDR')),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeContacts,
                    onChanged: (v) =>
                        setState(() => includeContacts = v ?? true),
                    title: Text(tr('Includi contatti personali')),
                  ),
                  const SizedBox(height: DrinSpace.s2),
                  TextField(
                    controller: pass1,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: tr('Passphrase (minimo 8 caratteri)'),
                    ),
                  ),
                  const SizedBox(height: DrinSpace.s2),
                  TextField(
                    controller: pass2,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: tr('Ripeti passphrase'),
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: DrinSpace.s2),
                    Text(
                      err!,
                      style: DrinText.detail.copyWith(color: c.busyText),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Annulla')),
            ),
            FilledButton(
              onPressed: () {
                if (pass1.text.length < ProfileBundleCodec.minPassphraseLength) {
                  setState(
                    () => err = tr(
                      'La passphrase deve avere almeno 8 caratteri.',
                    ),
                  );
                  return;
                }
                if (pass1.text != pass2.text) {
                  setState(() => err = tr('Le passphrase non coincidono.'));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(tr('Esporta')),
            ),
          ],
        );
      },
    ),
  );
  final passphrase = pass1.text;
  pass1.dispose();
  pass2.dispose();
  if (ok != true || !context.mounted) return;

  final loc = await getSaveLocation(
    suggestedName: '$safeName.drinprof',
    acceptedTypeGroups: [
      XTypeGroup(label: tr('Profilo DrinPhone'), extensions: const ['drinprof']),
    ],
  );
  if (loc == null) return;
  try {
    final sealed = await phone.exportProfileBundle(
      passphrase,
      includeSipPassword: includeSip,
      includePbxSecrets: includePbx,
      includeContacts: includeContacts,
    );
    await File(loc.path).writeAsString(sealed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Profilo esportato in {p}', {'p': loc.path})),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Esportazione non riuscita: {e}', {'e': '$e'})),
      ),
    );
  }
}

/// Importa un profilo cifrato `.drinprof` chiedendo la passphrase all'utente.
Future<void> showImportProfileDialog(
  BuildContext context,
  PhoneController phone, {
  VoidCallback? onImported,
}) async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: tr('Profilo DrinPhone'), extensions: const ['drinprof']),
    ],
  );
  if (file == null || !context.mounted) return;

  final raw = await file.readAsString();
  if (!context.mounted) return;
  final pass = TextEditingController();
  String? err;
  var busy = false;

  final importedName = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.drin;
        Future<void> submit() async {
          if (pass.text.isEmpty) {
            setState(() => err = tr('Inserisci la passphrase.'));
            return;
          }
          setState(() {
            busy = true;
            err = null;
          });
          try {
            final p = await phone.importProfileBundle(
              raw,
              pass.text,
              activate: !phone.loggedIn || phone.calls.isEmpty,
            );
            if (ctx.mounted) Navigator.of(ctx).pop(p.name);
          } catch (e) {
            if (ctx.mounted) {
              setState(() {
                busy = false;
                err = '$e';
              });
            }
          }
        }

        return AlertDialog(
          title: Text(tr('Importa profilo (.drinprof)')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  file.name,
                  style: DrinText.label.copyWith(color: c.muted),
                ),
                const SizedBox(height: DrinSpace.s3),
                TextField(
                  controller: pass,
                  obscureText: true,
                  autofocus: true,
                  enabled: !busy,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: tr('Passphrase del file'),
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: DrinSpace.s2),
                  Text(
                    err!,
                    style: DrinText.detail.copyWith(color: c.busyText),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text(tr('Annulla')),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? tr('Importazione…') : tr('Importa')),
            ),
          ],
        );
      },
    ),
  );
  pass.dispose();
  if (importedName == null || !context.mounted) return;
  onImported?.call();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tr('Profilo importato: {n}', {'n': importedName})),
    ),
  );
}

