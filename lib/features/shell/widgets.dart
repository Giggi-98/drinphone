// Componenti condivisi: avatar con stato linea + presenza, paginatore, badge.
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/sip/sip_engine.dart';

String initialsOf(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0])
    .take(2)
    .join()
    .toUpperCase();

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
      'away' => (Icons.schedule_rounded, c.ringing, tr('Assente')),
      'business_trip' => (Icons.flight_rounded, c.accent, tr('In trasferta')),
      'do_not_disturb' => (
        Icons.do_not_disturb_on_rounded,
        c.busy,
        tr('Non disturbare'),
      ),
      'lunch' => (Icons.restaurant_rounded, c.ringing, tr('Pausa pranzo')),
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
                    child: Text(
                      initialsOf(name),
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
  const CallIconButton({super.key, required this.onPressed, this.tooltip});
  final VoidCallback? onPressed;
  final String? tooltip;

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
      icon: const Icon(Icons.call_rounded, size: 18),
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
