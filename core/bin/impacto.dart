// Salud del constructor sobre TODO el dataset: cuántas unidades recién añadidas nacen limpias y
// cuántas arrastran avisos que el jugador no puede quitar.
//
// Se re-ejecuta. Es la forma de saber si un arreglo vale para las 36 facciones o solo para la que
// se miró de cerca.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  var unidades = 0, obligatorioSuelto = 0, piezas = 0, conAviso = 0, avisos = 0;
  final peores = <String, int>{};

  for (final faccion in dataset.factions) {
    final detachments = dataset.detachmentsOf(faccion);
    if (detachments.isEmpty) continue;
    for (final unidad in faccion.units) {
      final roster = Roster(faction: faccion, pointsLimit: 2000)
        ..detachments.add(detachments.first);
      final s = roster.selectionFor(unidad);
      roster.add(s);
      unidades++;

      var sueltas = 0;
      for (final nodo in s.descendantsAndSelf.toList()) {
        for (final o in roster.optionsFor(nodo)) {
          final min = o.constraints
              .where((c) => !c.isMax && c.field == 'selections')
              .fold<int>(0, (m, c) => c.value.round() > m ? c.value.round() : m);
          if (min < 1) continue;
          final puestas = nodo.children
              .where((h) => h.entryId == o.entryId)
              .fold<int>(0, (t, h) => t + h.count);
          if (puestas < min) sueltas++;
        }
      }
      if (sueltas > 0) {
        obligatorioSuelto++;
        piezas += sueltas;
      }

      // Avisos de «como máximo N, hay más»: esos no los puede causar el jugador en una unidad
      // recién puesta, así que son del motor.
      final sobra = roster.validate().where((v) => v.message.contains('como máximo')).toList();
      if (sobra.isNotEmpty) {
        conAviso++;
        avisos += sobra.length;
        peores[faccion.name] = (peores[faccion.name] ?? 0) + 1;
      }
    }
  }
  print('unidades revisadas: $unidades');
  print('con equipo obligatorio sin poner: $obligatorioSuelto  ($piezas piezas)');
  print('que nacen pasándose de un máximo: $conAviso  ($avisos avisos)');
  final orden = peores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in orden.take(6)) {
    print('   ${e.value.toString().padLeft(4)}  ${e.key}');
  }
}
