import 'package:flutter/material.dart';

import '../../app/theme.dart';

const _keys = [
  ('1', ''),
  ('2', 'ABC'),
  ('3', 'DEF'),
  ('4', 'GHI'),
  ('5', 'JKL'),
  ('6', 'MNO'),
  ('7', 'PQRS'),
  ('8', 'TUV'),
  ('9', 'WXYZ'),
  ('*', ''),
  ('0', '+'),
  ('#', ''),
];

class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final c = context.drin;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.45,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (d, l) in _keys)
          Material(
            color: c.keyBtn,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onKey(d),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    d,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: c.text,
                    ),
                  ),
                  Text(
                    l,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.5,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
