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
  final porFaccion = <String, ({int total, int listas})>{};

  for (final faccion in dataset.factions) {
    final detachments = dataset.detachmentsOf(faccion);
    if (detachments.isEmpty) continue;
    for (final unidad in faccion.units) {
      final roster = Roster(faction: faccion, pointsLimit: 2000)
        ..detachments.add(detachments.first);
      roster.add(roster.selectionFor(unidad));
      unidades++;
      final v = roster.validate();
      final prev = porFaccion[faccion.name] ?? (total: 0, listas: 0);
      porFaccion[faccion.name] =
          (total: prev.total + 1, listas: prev.listas + (v.isEmpty ? 1 : 0));
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
  print('');
  print('por facción — listas / total:');
  final tabla = porFaccion.entries.toList()
    ..sort((a, b) => (a.value.listas / a.value.total)
        .compareTo(b.value.listas / b.value.total));
  for (final e in tabla) {
    final pct = (e.value.listas * 100 / e.value.total).round();
    print('   ${e.value.listas.toString().padLeft(4)} / ${e.value.total.toString().padLeft(4)}'
        '  ${pct.toString().padLeft(3)} %   ${e.key}');
  }
}
