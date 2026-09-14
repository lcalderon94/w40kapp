import 'package:flutter/material.dart';

import '../tema.dart';

/// Convierte el texto del dataset en trozos con estilo.
///
/// BattleScribe marca el texto con `**negrita**` y con `^^palabra clave^^`, y las anida
/// (`^^**Vehicle**^^`). Se resuelven con dos interruptores en vez de con un analizador: el texto no
/// tiene estructura, solo marcas que se abren y se cierran, y así una marca suelta o sin cerrar
/// —que las hay— degrada a texto normal en vez de romper la ficha.
List<InlineSpan> trozosDeRegla(String texto, TextStyle base) {
  final trozos = <InlineSpan>[];
  final acumulado = StringBuffer();
  var negrita = false;
  var clave = false;

  void volcar() {
    if (acumulado.isEmpty) return;
    trozos.add(TextSpan(
      text: acumulado.toString(),
      style: clave
          ? base.merge(Tema.clave)
          : (negrita ? base.copyWith(fontWeight: FontWeight.w700) : base),
    ));
    acumulado.clear();
  }

  var i = 0;
  while (i < texto.length) {
    if (texto.startsWith('**', i)) {
      volcar();
      negrita = !negrita;
      i += 2;
    } else if (texto.startsWith('^^', i)) {
      volcar();
      clave = !clave;
      i += 2;
    } else if (texto.startsWith('<ins>', i)) {
      i += 5;
    } else if (texto.startsWith('</ins>', i)) {
      i += 6;
    } else {
      acumulado.write(texto[i]);
      i++;
    }
  }
  volcar();
  return trozos;
}

/// Un texto de regla del dataset, con sus marcas ya interpretadas.
class TextoDeRegla extends StatelessWidget {
  const TextoDeRegla(this.texto, {super.key, this.estilo});

  final String texto;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    final base = estilo ??
        const TextStyle(color: Tema.texto, fontSize: 14, height: 1.45);
    return Text.rich(TextSpan(children: trozosDeRegla(texto, base)));
  }
}
