// Cuántas unidades llegan listas para jugar nada más añadirlas, en todas las facciones.
//
// Una unidad recién añadida debería traer el equipo de su hoja de datos y no avisar de nada que el
// jugador no haya decidido. Lo que avise de más es equipo que la app te obliga a poner a mano.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  var unidades = 0, limpias = 0, avisos = 0;
  final peores = <String, int>{};

  for (final faccion in dataset.factions) {
    final detachments = dataset.detachmentsOf(faccion);
    if (detachments.isEmpty) continue;
    for (final unidad in faccion.units) {
      final roster = Roster(faction: faccion, pointsLimit: 2000)
        ..detachments.add(detachments.first);
      roster.add(roster.selectionFor(unidad));
      unidades++;
      final v = roster.validate();
      if (v.isEmpty) {
        limpias++;
      } else {
        avisos += v.length;
        peores[faccion.name] = (peores[faccion.name] ?? 0) + 1;
      }
    }
  }
  print('unidades: $unidades');
  print('llegan listas, sin nada pendiente: $limpias '
      '(${(limpias * 100 / unidades).toStringAsFixed(1)} %)');
  print('llegan pidiendo algo: ${unidades - limpias}  ($avisos avisos)');
  final orden = peores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in orden.take(6)) {
    print('   ${e.value.toString().padLeft(4)}  ${e.key}');
  }
}
