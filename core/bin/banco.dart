// Banco de pruebas manual: monta una unidad desde el motor como lo haría la interfaz, elige
// opciones por nombre a cualquier profundidad y enseña el árbol. Sirve para comprobar a mano lo
// que la pantalla debería dejar hacer.
import 'dart:io';

import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

/// Pone [veces] copias de la opción [nombre] bajo [padre], como hace la interfaz.
void elegir(Roster roster, Selection padre, String nombre, [int veces = 1]) {
  for (var i = 0; i < veces; i++) {
    final opcion = roster.optionsFor(padre).where((o) => o.name == nombre).firstOrNull;
    if (opcion == null) {
      print('  !! «$nombre» no se ofrece bajo «${padre.name}»');
      return;
    }
    // Un grupo que solo deja elegir una cosa se comporta como un botón de radio: lo nuevo
    // sustituye a lo viejo. Apilarlo es lo que hacía la pantalla, y por eso incumplía siempre.
    final grupo = padre.groups.where((g) => g.id == opcion.groupId).firstOrNull;
    final maximo = grupo?.constraints
        .where((c) => c.isMax && c.field == 'selections')
        .map((c) => c.value.round())
        .fold<int?>(null, (m, v) => m == null || v < m ? v : m);
    if (maximo == 1) {
      padre.children.removeWhere((h) => h.groupId == opcion.groupId);
    }
    final puesta = padre.children.where((h) => h.entryId == opcion.entryId).firstOrNull;
    if (puesta != null) {
      puesta.count++;
    } else {
      padre.addChild(opcion);
    }
  }
}

Selection hijo(Selection padre, String nombre) =>
    padre.children.firstWhere((h) => h.name == nombre);

void main() async {
  final dataset = await Dataset.load(_dir());
  final dg = dataset.factionNamed('Chaos - Death Guard');
  final roster = Roster(faction: dg, pointsLimit: 2000)
    ..detachments.add(dataset.detachmentsOf(dg).first);
  final u = roster.selectionFor(dg.units.firstWhere((x) => x.name == 'Plague Marines'));
  roster.add(u);

  print('=== lo que pidió el usuario: 2 blight, 2 plasma, 2 spewer, 3 heavy + campeón ===\n');
  elegir(roster, u, 'Plague Marine w/ blight launcher', 2);
  elegir(roster, u, 'Plague Marine w/ plasma gun', 2);
  elegir(roster, u, 'Plague Marine w/ plague spewer', 2);
  elegir(roster, u, 'Plague Marine w/ heavy plague weapon', 3);

  final campeon = hijo(u, 'Plague Champion');
  elegir(roster, campeon, 'Power fist');
  elegir(roster, campeon, 'Plasma gun');

  roster.applyModifiers();
  arbol(roster, u, 0);
  final modelos = u.descendantsAndSelf.where((s) => s.type == 'model').fold(0, (t, s) => t + s.count);
  print('\nminiaturas: $modelos');
  print('puntos de la unidad: ${u.points}   (lista: ${roster.points})');
  print('modifiers de coste sin evaluar: ${u.unresolvedCostModifiers}');
  print('avisos: ${roster.validate().isEmpty ? "ninguno" : ""}');
  for (final v in roster.validate()) {
    print('  - ${v.message}');
  }
}

void arbol(Roster roster, Selection s, int nivel) {
  final pad = '  ' * nivel;
  print('$pad• ${s.name}  x${s.count}  ${s.pointsEach} pts/u');
  for (final o in roster.optionsFor(s)) {
    print('$pad  ○ ofrece: ${o.name}  (grupo: ${o.groupName})');
  }
  for (final h in s.children) {
    arbol(roster, h, nivel + 1);
  }
}
