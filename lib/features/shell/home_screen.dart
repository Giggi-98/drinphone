import 'package:flutter/material.dart';

import '../../app/phone_controller.dart';
import '../../app/theme.dart';
import '../../core/security/settings_store.dart';
import '../../core/sip/sip_engine.dart';
import '../account/account_dialog.dart';
import '../call/call_panel.dart';
import '../call/keypad.dart';

/// Struttura a pannelli (proposta D): barra sezioni, barra composizione con
/// tastierino a comparsa, griglia interni. Gruppi: assenti di default (DECISIONS).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dial = TextEditingController();
  bool _keypadOpen = false;

  PhoneController get p => widget.phone;

  @override
  void initState() {
    super.initState();
    p.addListener(_onPhone);
  }

  @override
  void dispose() {
    p.removeListener(_onPhone);
    _dial.dispose();
    super.dispose();
  }

  void _onPhone() {
    final n = p.notice;
    if (n != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
      p.clearNotice();
    }
    setState(() {});
  }

  void _call(String number) {
    p.dial(number);
    setState(() => _keypadOpen = false);
  }

  void _openAccount() => showDialog<void>(
    context: context,
    builder: (_) => AccountDialog(phone: p),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final call = p.call;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(onSettings: _openAccount),
          Expanded(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(c),
                    if (p.engineError != null)
                      _banner(c, 'Motore SIP non avviato: ${p.engineError}'),
                    if (p.engineError == null && p.settings.account == null)
                      _banner(
                        c,
                        'Nessun account SIP configurato.',
                        action: ('Configura', _openAccount),
                      ),
                    Expanded(
                      child: _ExtensionsView(phone: p, onCall: _call),
                    ),
                  ],
                ),
                if (_keypadOpen)
                  Positioned(
                    top: 64,
                    right: 140,
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x47000000),
                            blurRadius: 32,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Keypad(
                        onKey: (d) => setState(() => _dial.text += d),
                      ),
                    ),
                  ),
                if (call != null)
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: CallPanel(phone: p, call: call),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(DrinColors c, String text, {(String, VoidCallback)? action}) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.ringing),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: TextStyle(color: c.text)),
            ),
            if (action != null)
              TextButton(onPressed: action.$2, child: Text(action.$1)),
          ],
        ),
      );

  Widget _topBar(DrinColors c) {
    final reg = p.registration;
    final (dot, label) = switch (reg.status) {
      RegistrationStatus.ok => (c.ok, 'Registrato'),
      RegistrationStatus.progress => (c.ringing, 'Registrazione…'),
      RegistrationStatus.failed => (c.busy, 'Errore registrazione'),
      _ => (c.muted, 'Non registrato'),
    };
    final account = p.settings.account;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: reg.message,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(color: c.text)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.field,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dial,
                    onSubmitted: _call,
                    style: TextStyle(
                      fontFamily: monoFont,
                      fontSize: 15,
                      color: c.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Numero o interno',
                      // Il segnaposto eredita il monospazio del campo: lo riporta al testo normale.
                      hintStyle: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontSize: 14,
                        color: c.muted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                _iconButton(
                  c,
                  Icons.dialpad,
                  'Tastierino',
                  c.keyBtn,
                  c.accent,
                  () => setState(() => _keypadOpen = !_keypadOpen),
                ),
                const SizedBox(width: 4),
                _iconButton(
                  c,
                  Icons.call,
                  'Chiama',
                  DrinColors.callGreen,
                  Colors.white,
                  p.canDial ? () => _call(_dial.text) : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _openAccount,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: c.avatar,
                    child: Text(
                      account?.username ?? '?',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account == null
                            ? 'Nessun account'
                            : (account.displayName.isNotEmpty
                                  ? account.displayName
                                  : account.username),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: c.text,
                        ),
                      ),
                      Text(
                        account?.domain ?? 'Configura',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    DrinColors c,
    IconData icon,
    String tip,
    Color bg,
    Color fg,
    VoidCallback? onTap,
  ) => Tooltip(
    message: tip,
    child: Material(
      color: onTap == null ? c.keyBtn : bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: onTap == null ? c.muted : fg),
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    Widget item(
      IconData icon,
      String label,
      bool selected,
      VoidCallback? onTap,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.keyBtn : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(icon, size: 18, color: selected ? c.accent : c.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? c.accent : c.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      width: 216,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
      decoration: BoxDecoration(
        color: c.side,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'D',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'DrinPhone',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          item(Icons.people_outline, 'Interni', true, () {}),
          const Spacer(),
          item(Icons.tune, 'Impostazioni', false, onSettings),
        ],
      ),
    );
  }
}

class _ExtensionsView extends StatelessWidget {
  const _ExtensionsView({required this.phone, required this.onCall});
  final PhoneController phone;
  final ValueChanged<String> onCall;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi interno'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: number,
                decoration: const InputDecoration(
                  labelText: 'Numero / interno',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (ok == true && number.text.trim().isNotEmpty) {
      final n = number.text.trim();
      await phone.addExtension(
        Extension(name.text.trim().isEmpty ? n : name.text.trim(), n),
      );
    }
    name.dispose();
    number.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final list = phone.settings.extensions;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Tutti gli interni',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${list.length} interni',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi interno'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Nessun interno. Aggiungi quelli che chiami più spesso.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 116,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ExtensionCard(
                      ext: list[i],
                      canCall: phone.canDial,
                      onCall: () => onCall(list[i].number),
                      onRemove: () => phone.removeExtension(list[i]),
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Stato interni (BLF): non ancora disponibile',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.ext,
    required this.canCall,
    required this.onCall,
    required this.onRemove,
  });
  final Extension ext;
  final bool canCall;
  final VoidCallback onCall;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    final initials = ext.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: c.avatar,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: c.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.muted, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: ext.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: c.text,
                            ),
                          ),
                          TextSpan(
                            text: ' ${ext.number}',
                            style: TextStyle(
                              fontFamily: monoFont,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Sconosciuto',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.keyBtn,
                    foregroundColor: c.accent,
                    minimumSize: const Size.fromHeight(36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: canCall ? onCall : null,
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Chiama'),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<void>(
                tooltip: 'Altre azioni',
                icon: Icon(Icons.more_horiz, color: c.muted),
                itemBuilder: (_) => [
                  PopupMenuItem(onTap: onRemove, child: const Text('Rimuovi')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
