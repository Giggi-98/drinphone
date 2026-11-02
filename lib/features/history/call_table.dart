// Tabella delle chiamate (DESIGN.md §6 "Tabella chiamate"): intestazione,
// colonne fisse o flessibili, righe dense con hover e Richiama che compare
// al passaggio (sempre visibile al tocco). Usata dal registro di questo PC e
// dal CDR del PBX.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../shell/widgets.dart';

/// Colonna: larghezza fissa o quota dello spazio libero; sotto [hideBelow]
/// pixel di tabella la colonna sparisce (prima quelle meno importanti).
class CallColumn {
  const CallColumn(
    this.label, {
    this.width = 0,
    this.flex = 0,
    this.end = false,
    this.hideBelow = 0,
    this.sortKey,
  });
  final String label;
  final double width;
  final int flex;

  /// Allineata a destra (durate).
  final bool end;
  final double hideBelow;

  /// Se non nullo, un clic sull'intestazione ordina per questa colonna.
  final Object? sortKey;
}

/// Una riga: celle nell'ordine delle colonne, numero da richiamare.
class CallRow {
  const CallRow({required this.cells, this.call, this.callTooltip, this.onTap});
  final List<Widget> cells;
  final VoidCallback? call;
  final String? callTooltip;

  /// Clic sulla riga (dettaglio).
  final VoidCallback? onTap;
}

class CallTable extends StatelessWidget {
  const CallTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.sortKey,
    this.descending = true,
    this.onSort,
  });
  final List<CallColumn> columns;
  final List<CallRow> rows;

  /// Ordinamento in corso (freccia sull'intestazione) e cambio di colonna.
  final Object? sortKey;
  final bool descending;
  final ValueChanged<Object>? onSort;

  /// In fondo alla lista (Carica altre, avanzamento).
  final Widget? footer;

  static const rowHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return LayoutBuilder(
      builder: (context, box) {
        final shown = [
          for (var i = 0; i < columns.length; i++)
            if (box.maxWidth >= columns[i].hideBelow) i,
        ];
        Widget line(List<Widget> cells) => Row(
          children: [
            for (final i in shown) _cell(columns[i], cells[i]),
            const SizedBox(width: 48),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: DrinSpace.s3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: line([for (final col in columns) _header(col, c)]),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: DrinSpace.s1),
                itemCount: rows.length + (footer == null ? 0 : 1),
                itemBuilder: (_, i) => i == rows.length
                    ? footer!
                    : Column(
                        children: [
                          _HoverRow(row: rows[i], child: line(rows[i].cells)),
                          if (i < rows.length - 1)
                            Divider(height: 1, thickness: 1, color: c.line),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Intestazione: testo; se ordinabile, cliccabile con la freccia.
  Widget _header(CallColumn col, DrinColors c) {
    final key = col.sortKey;
    final on = key != null && key == sortKey;
    final text = Text(
      col.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: col.end ? TextAlign.end : TextAlign.start,
      style: DrinText.label.copyWith(color: on ? c.primary : c.muted),
    );
    final sort = onSort;
    if (key == null || sort == null) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(DrinRadius.control),
      onTap: () => sort(key),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: text),
          const SizedBox(width: 2),
          Icon(
            !on
                ? Icons.unfold_more_rounded
                : descending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 14,
            color: on ? c.primary : c.muted,
          ),
        ],
      ),
    );
  }

  static Widget _cell(CallColumn col, Widget child) {
    final aligned = Align(
      alignment: col.end ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    final padded = Padding(
      padding: const EdgeInsets.only(right: DrinSpace.s3),
      child: aligned,
    );
    return col.flex > 0
        ? Expanded(flex: col.flex, child: padded)
        : SizedBox(width: col.width, child: padded);
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.row, required this.child});
  final CallRow row;
  final Widget child;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final fast = DrinMotion.of(context, DrinMotion.fast);
    // Senza puntatore (tocco) Richiama resta sempre visibile.
    final mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;
    final row = widget.row;
    return MouseRegion(
      cursor: row.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.onTap,
        child: AnimatedContainer(
          duration: fast,
          curve: DrinMotion.curve,
          height: CallTable.rowHeight,
          padding: const EdgeInsets.only(left: DrinSpace.s3),
          decoration: BoxDecoration(
            color: _hover ? c.raised : c.raised.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(DrinRadius.row),
          ),
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              widget.child,
              AnimatedOpacity(
                duration: fast,
                opacity: _hover || !mouse ? 1 : 0,
                child: CallIconButton(
                  tooltip: row.callTooltip,
                  onPressed: row.call,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Due righe: principale (nome) e secondaria (numero in `number`).
class TwoLine extends StatelessWidget {
  const TwoLine(this.top, {super.key, this.bottom, this.color, this.extra});
  final String top;
  final String? bottom;
  final Color? color;

  /// Terza informazione sotto (es. "risposto da", nota).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DrinText.heading.copyWith(color: color ?? c.ink),
        ),
        if (bottom != null && bottom!.isNotEmpty && extra == null)
          Text(
            bottom!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DrinText.number.copyWith(color: c.muted),
          ),
        ?extra,
      ],
    );
  }
}

/// Chi parla in una cella: nome e numero, o solo il numero.
TwoLine party(String name, String number, {Color? color, Widget? extra}) =>
    name.isNotEmpty && name != number
    ? TwoLine(name, bottom: number, color: color, extra: extra)
    : TwoLine(number.isEmpty ? '—' : number, color: color, extra: extra);

/// Riga secondaria con icona (risposto da, nota).
class SubLine extends StatelessWidget {
  const SubLine(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Row(
      children: [
        Icon(icon, size: 13, color: c.primary),
        const SizedBox(width: DrinSpace.s1),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DrinText.detail.copyWith(color: c.muted),
          ),
        ),
      ],
    );
  }
}

/// Ora: orario grande, giorno sotto.
class WhenCell extends StatelessWidget {
  const WhenCell(this.time, {super.key});
  final DateTime? time;

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final t = time;
    if (t == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    final day = switch (days) {
      0 => tr('Oggi'),
      1 => tr('Ieri'),
      _ => '${_two(t.day)}/${_two(t.month)}/${t.year}',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
          style: DrinText.number.copyWith(color: c.ink),
        ),
        Text(day, style: DrinText.detail.copyWith(color: c.muted)),
      ],
    );
  }
}

/// Tipo di chiamata: icona e parola, senza fondo.
class KindCell extends StatelessWidget {
  const KindCell(this.icon, this.label, {super.key, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? c.primary),
        const SizedBox(width: DrinSpace.s2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DrinText.body.copyWith(color: c.ink),
          ),
        ),
      ],
    );
  }
}

/// Esito: pillola con spia (risposta `free`, persa/non riuscita `busy`,
/// casella vocale `primary`, il resto `away`).
class OutcomePill extends StatelessWidget {
  const OutcomePill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DrinSpace.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DrinRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DrinText.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Durata in cifre tabulari: 0:47, 12:05, 1:02:03; "—" se zero.
class DurationCell extends StatelessWidget {
  const DurationCell(this.seconds, {super.key, this.strong = false});
  final int seconds;
  final bool strong;

  static String format(int s) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
    return h > 0 ? '$h:${two(m)}:${two(r)}' : '$m:${two(r)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return Text(
      seconds <= 0 ? '—' : format(seconds),
      style: DrinText.number.copyWith(color: strong ? c.ink : c.muted),
    );
  }
}
