import 'package:flutter/material.dart';

import 'theme.dart';

/// Canale di rilascio mostrato nell'interfaccia e nel titolo della finestra.
const releaseChannel = 'Alpha';

/// Versione della build: la passa `tool/build_installer.ps1` da pubspec.yaml.
const buildVersion = String.fromEnvironment(
  'DRIN_VERSION',
  defaultValue: 'dev',
);

/// Blu del logo DRIN (nuvola di DRIN-CLOUD-LOGO).
const drinBlue = Color(0xFF1380C6);

/// Logo "Drin!" monocromatico: blu DRIN sul tema chiaro, testo chiaro sullo
/// scuro. Un solo asset bianco, colorato qui.
class DrinLogo extends StatelessWidget {
  const DrinLogo({super.key, this.height = 32});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      'assets/brand/drin_logo.png',
      height: height,
      color: dark ? context.drin.text : drinBlue,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'DRIN',
    );
  }
}

/// Etichetta del canale ("ALPHA"), con la versione nel tooltip.
class ChannelBadge extends StatelessWidget {
  const ChannelBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    // Sul chiaro l'ambra pieno non si legge: testo ambra scuro.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? c.ringing
        : const Color(0xFF8A5A00);
    return Tooltip(
      message: '$releaseChannel $buildVersion',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.ringing.withValues(alpha: 0.16),
          border: Border.all(color: c.ringing),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          releaseChannel.toUpperCase(),
          style: TextStyle(
            color: ink,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
