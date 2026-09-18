// Convierte el listado de opciones de equipo de las index cards en el JSON que lee la app.
//
// El texto viene por facción y por unidad, en una línea cada una:
//
//     [Death Guard]
//     PLAGUE MARINES: For every 5 models in this unit, … | The Plague Champion’s … | …
//
// Cada línea se parte por «|», que es como el original separa una opción de otra, y se guarda con
// el nombre de la unidad normalizado, que es con lo que se busca luego.
//
// Se ejecuta con: dart run tool/notas-de-equipo.dart
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final origen = File(args.isEmpty ? 'data/wargear/opciones-de-equipo.txt' : args.first);
  final destino =
      File(args.length > 1 ? args[1] : 'data/wargear/notas-de-equipo.json');

  final notas = <String, Map<String, dynamic>>{};
  var faccion = '';
  var conTexto = 0;

  for (final linea in await origen.readAsLines()) {
    if (linea.startsWith('[')) {
      faccion = linea.substring(1, linea.length - 1).trim();
      continue;
    }
    final corte = linea.indexOf(':');
    if (corte < 0) continue;
    final unidad = linea.substring(0, corte).trim();
    final cuerpo = linea.substring(corte + 1).trim();
    if (cuerpo.isEmpty || cuerpo == 'None') continue;

    final opciones = [
      for (final trozo in cuerpo.split('|'))
        if (trozo.trim().isNotEmpty) trozo.trim(),
    ];
    if (opciones.isEmpty) continue;
    conTexto++;
    notas[clave(unidad)] = {
      'faccion': faccion,
      'unidad': unidad,
      'opciones': opciones,
    };
  }

  await destino.parent.create(recursive: true);
  await destino.writeAsString(const JsonEncoder.withIndent('  ').convert(notas));
  stdout.writeln('$conTexto unidades con opciones de equipo → ${destino.path}');
}

/// La clave con la que se busca una unidad: sin tildes, sin signos y sin mayúsculas.
String clave(String nombre) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  return nombre
      .toLowerCase()
      .split('')
      .map((c) => tildes[c] ?? c)
      .join()
      .replaceAll(RegExp(r'\[(legends|crucible)\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}
