// Qué parte del equipo de cada unidad quedaba fuera de la pantalla vieja, en TODAS las facciones.
//
// La pantalla vieja pintaba un solo nivel: las opciones que cuelgan directamente de la unidad.
// Todo lo que viviera por debajo —el equipo de una miniatura concreta, las modificaciones de un
// arma— no se podía tocar. Esto cuenta cuánto era.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  var unidades = 0, conFondo = 0, piezasAlFondo = 0, conRadio = 0;
  var maxProfundidad = 0;
  final porFaccion = <String, ({int unidades, int rotas})>{};

  for (final faccion in dataset.factions) {
    final detachments = dataset.detachmentsOf(faccion);
    if (detachments.isEmpty) continue;
    var deLaFaccion = 0, rotasDeLaFaccion = 0;

    for (final unidad in faccion.units) {
      final roster = Roster(faction: faccion, pointsLimit: 2000)
        ..detachments.add(detachments.first);
      final raiz = roster.selectionFor(unidad);
      roster.add(raiz);
      unidades++;
      deLaFaccion++;

      // Nivel 1: lo que la pantalla vieja sí pintaba.
      var frontera = raiz.children.toList();
      var profundidad = 1;
      var alFondo = 0;
      var tieneRadio = roster.optionsFor(raiz).any((o) =>
          o.groupId != null && _maximo(roster, raiz, o.groupId!) == 1);

      // Niveles 2 en adelante: lo que no existía en ninguna parte.
      while (frontera.isNotEmpty && profundidad < 8) {
        final siguiente = <Selection>[];
        for (final nodo in frontera) {
          final ofrece = roster.optionsFor(nodo);
          alFondo += ofrece.length;
          if (ofrece.any((o) =>
              o.groupId != null && _maximo(roster, nodo, o.groupId!) == 1)) {
            tieneRadio = true;
          }
          siguiente.addAll(nodo.children);
        }
        if (alFondo > 0 && profundidad + 1 > maxProfundidad) {
          maxProfundidad = profundidad + 1;
        }
        frontera = siguiente;
        profundidad++;
      }

      if (alFondo > 0) {
        conFondo++;
        rotasDeLaFaccion++;
        piezasAlFondo += alFondo;
      }
      if (tieneRadio) conRadio++;
    }
    porFaccion[faccion.name] = (unidades: deLaFaccion, rotas: rotasDeLaFaccion);
  }

  print('facciones: ${porFaccion.length}');
  print('unidades: $unidades');
  print('');
  print('con equipo por debajo del primer nivel (invisible en la pantalla vieja):');
  print('   $conFondo unidades  (${(conFondo * 100 / unidades).toStringAsFixed(1)} %)'
      '  ·  $piezasAlFondo piezas');
  print('anidamiento máximo encontrado: $maxProfundidad niveles');
  print('');
  print('con algún grupo de una sola opción (que la pantalla vieja apilaba mal):');
  print('   $conRadio unidades  (${(conRadio * 100 / unidades).toStringAsFixed(1)} %)');
  print('');
  print('por facción — unidades afectadas / total:');
  final orden = porFaccion.entries.toList()
    ..sort((a, b) => b.value.rotas.compareTo(a.value.rotas));
  for (final e in orden) {
    final pct = e.value.unidades == 0
        ? 0
        : (e.value.rotas * 100 / e.value.unidades).round();
    print('   ${e.value.rotas.toString().padLeft(4)} / ${e.value.unidades.toString().padLeft(4)}'
        '  ${pct.toString().padLeft(3)} %   ${e.key}');
  }
}

int? _maximo(Roster roster, Selection dueno, String groupId) {
  final grupo = dueno.groups.where((g) => g.id == groupId).firstOrNull;
  return grupo == null ? null : roster.groupUsage(dueno, grupo).maximo;
}
