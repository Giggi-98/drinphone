// Componenti condivisi: avatar con stato linea + presenza, paginatore, badge.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';

/// Iniziali delle parole che cominciano con una lettera ('' per "305", "*2").
String initialsOf(String name) => name
    .split(RegExp(r'\s+'))
    .where(
      (w) => w.isNotEmpty && RegExp(r'\p{L}', unicode: true).hasMatch(w[0]),
    )
    .map((w) => w[0])
    .take(2)
    .join()
    .toUpperCase();

/// Il nome non dice niente di più del numero ("208", "211 211"): si mostra
/// solo il numero, senza doppioni.
bool nameIsNumber(String name, String number) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.isEmpty || words.every((w) => w == number);
}

/// Iniziali, oppure un'icona se il nome è solo un numero o un codice.
Widget initialsOrIcon(
  String name, {
  required TextStyle style,
  IconData icon = Icons.dialpad_rounded,
}) {
  final i = initialsOf(name);
  return i.isEmpty
      ? Icon(icon, size: (style.fontSize ?? 14) * 1.15, color: style.color)
      : Text(i, style: style);
}

/// Stato linea (BLF) a parole, per tooltip e lettori di schermo.
String blfLabel(BlfStatus? s) => switch (s) {
  BlfStatus.idle => tr('Libero'),
  BlfStatus.busy => tr('Occupato'),
  BlfStatus.ringing => tr('Squilla'),
  BlfStatus.offline => tr('Non registrato'),
  _ => tr('Stato sconosciuto'),
};

/// Presenza Yeastar: (icona, colore, etichetta); null se assente.
(IconData, Color, String)? presenceOf(DrinColors c, String presence) =>
    switch (presence) {
      'available' => (Icons.check_circle_rounded, c.ok, tr('Disponibile')),
      'away' => (Icons.schedule_rounded, c.away, tr('Assente')),
      'business_trip' => (Icons.flight_rounded, c.accent, tr('In trasferta')),
      'do_not_disturb' => (
        Icons.do_not_disturb_on_rounded,
        c.busy,
        tr('Non disturbare'),
      ),
      'lunch' => (Icons.restaurant_rounded, c.away, tr('Pausa pranzo')),
      'off_work' => (Icons.bedtime_rounded, c.muted, tr('Fuori ufficio')),
      _ => null,
    };

/// Avatar con anello = stato linea e simbolo in basso a destra = presenza.
class StatusAvatar extends StatelessWidget {
  const StatusAvatar({
    super.key,
    required this.name,
    this.blf,
    this.presence = '',
    this.size = 40,
    this.stale = false,
  });
  final String name;
  final BlfStatus? blf;

  /// Ultimo stato noto, non ancora confermato dal PBX: anello attenuato.
  final bool stale;
  final String presence;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final ring = switch (blf) {
      BlfStatus.idle => c.ok,
      BlfStatus.busy => c.busy,
      BlfStatus.ringing => c.ringing,
      _ => null,
    }?.withValues(alpha: stale ? 0.35 : 1);
    final offline = blf == BlfStatus.offline;
    final p = presenceOf(c, presence);
    final label = [
      blfLabel(blf),
      if (stale) tr('da confermare'),
      if (p != null) p.$3,
    ].join(' · ');
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: size + 6,
          height: size + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: size + 6,
                height: size + 6,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ring ?? (offline ? c.border : Colors.transparent),
                    width: 2,
                  ),
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: offline ? 0.45 : 1,
                  child: CircleAvatar(
                    backgroundColor: c.avatar,
                    child: initialsOrIcon(
                      name,
                      style: TextStyle(
                        fontSize: size * 0.32,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: p == null
                      ? const SizedBox.shrink()
                      : Container(
                          key: ValueKey(presence),
                          decoration: BoxDecoration(
                            color: c.card,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(1.5),
                          child: Icon(p.$1, size: size * 0.38, color: p.$2),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transizione morbida (dissolvenza + leggero scorrimento) al cambio di sezione o scheda.
class AnimatedSectionSwitch extends StatelessWidget {
  const AnimatedSectionSwitch({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Animazione d'ingresso per menu a tendina, popup di ricerca e tastierino.
class AnimatedPopup extends StatelessWidget {
  const AnimatedPopup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -8),
          child: Transform.scale(
            scale: 0.96 + 0.04 * t,
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Pulsante tondo di chiamata (solo simbolo, testo nel tooltip).
class CallIconButton extends StatelessWidget {
  const CallIconButton({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.icon = Icons.call_rounded,
  });
  final VoidCallback? onPressed;
  final String? tooltip;

  /// `Icons.videocam_rounded` per la videochiamata.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return IconButton.filledTonal(
      tooltip: tooltip ?? tr('Chiama'),
      style: IconButton.styleFrom(
        backgroundColor: c.keyBtn,
        foregroundColor: c.accent,
        disabledBackgroundColor: c.keyBtn.withValues(alpha: 0.4),
        minimumSize: const Size(40, 40),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}

/// Badge numerico per la barra laterale.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.alert = false});
  final int count;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: alert ? c.busy : c.keyBtn,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: alert ? Colors.white : c.text,
        ),
      ),
    );
  }
}

/// Elenco lungo diviso in pagine: restituisce la fetta e disegna il pager.
class Pager extends StatelessWidget {
  const Pager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
  });
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;

  int get pages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  static List<T> slice<T>(List<T> list, int page, int pageSize) {
    final start = page * pageSize;
    if (start >= list.length) return const [];
    return list.sublist(start, (start + pageSize).clamp(0, list.length));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    if (pages <= 1) return const SizedBox.shrink();
    // Al più 7 numeri: prima, ultima e vicine a quella corrente.
    final shown = <int>{
      0,
      pages - 1,
      for (var i = page - 2; i <= page + 2; i++)
        if (i >= 0 && i < pages) i,
    }.toList()..sort();
    final from = page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);
    Widget num(int i) {
      final on = i == page;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: on ? c.keyBtn : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPage(i),
            child: Container(
              constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: on ? c.accent : c.text,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final items = <Widget>[];
    for (var k = 0; k < shown.length; k++) {
      if (k > 0 && shown[k] - shown[k - 1] > 1) {
        items.add(Text('…', style: TextStyle(color: c.muted)));
      }
      items.add(num(shown[k]));
    }
    return Row(
      children: [
        Text(
          tr('{a}–{b} di {n}', {'a': from, 'b': to, 'n': total}),
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        const Spacer(),
        IconButton(
          tooltip: tr('Pagina precedente'),
          onPressed: page > 0 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        ...items,
        IconButton(
          tooltip: tr('Pagina successiva'),
          onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// Voce di un menu contestuale: icona, testo, azione (null = disattivata).
typedef MenuAction = (IconData, String, VoidCallback?);

/// Menu del tasto destro nel punto [at]: stesse righe del menu account
/// (icona `muted` a sinistra, testo `body`).
Future<void> showActionsMenu(
  BuildContext context,
  Offset at,
  List<MenuAction?> actions,
) {
  final c = context.drin;
  return showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      for (final a in actions)
        if (a == null)
          const PopupMenuDivider()
        else
          PopupMenuItem<void>(
            height: 40,
            enabled: a.$3 != null,
            onTap: a.$3,
            child: Row(
              children: [
                Icon(a.$1, size: 18, color: c.muted),
                const SizedBox(width: DrinSpace.s3),
                Text(a.$2),
              ],
            ),
          ),
    ],
  );
}

/// Copia [text] negli appunti e lo dice con un avviso breve.
void copyWithToast(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(tr('Copiato: {t}', {'t': text})),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Azione "Copia numero" pronta per [showActionsMenu].
MenuAction copyAction(BuildContext context, String number) => (
  Icons.content_copy_rounded,
  tr('Copia numero'),
  number.isEmpty ? null : () => copyWithToast(context, number),
);

/// Legenda dei simboli: anello dell'avatar = stato della linea, simbolo in
/// basso a destra = presenza Yeastar.
Future<void> showStatusLegend(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) {
    final c = ctx.drin;
    Widget row(Widget symbol, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DrinSpace.s1),
      child: Row(
        children: [
          SizedBox(width: 28, child: Center(child: symbol)),
          const SizedBox(width: DrinSpace.s3),
          Text(label, style: DrinText.body.copyWith(color: c.ink)),
        ],
      ),
    );
    Widget ring(Color? color) => Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color ?? c.line, width: 2),
      ),
    );
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: DrinSpace.s3, bottom: DrinSpace.s1),
      child: Text(t, style: DrinText.label.copyWith(color: c.muted)),
    );
    return AlertDialog(
      title: Text(tr('Legenda degli stati')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            head(tr('Anello: stato della linea')),
            row(ring(c.ok), tr('Libero')),
            row(ring(c.busy), tr('Occupato')),
            row(ring(c.ringing), tr('Squilla')),
            row(ring(null), tr('Non registrato')),
            head(tr('Simbolo: presenza')),
            for (final st in const [
              'available',
              'away',
              'do_not_disturb',
              'lunch',
              'business_trip',
              'off_work',
            ])
              if (presenceOf(c, st) case final p?)
                row(Icon(p.$1, size: 18, color: p.$2), p.$3),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('Chiudi')),
        ),
      ],
    );
  },
);
