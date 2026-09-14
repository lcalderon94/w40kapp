// Sonda: qué ve el motor de una opción recién creada, con sus restricciones resueltas.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  final dg = dataset.factionNamed('Chaos - Death Guard');
  final roster = Roster(faction: dg, pointsLimit: 2000)
    ..detachments.add(dataset.detachmentsOf(dg).first);
  final u = roster.selectionFor(dg.units.firstWhere((x) => x.name == 'Plague Marines'));
  roster.add(u);

  for (final nombre in ['Plague Marine w/ plasma gun', 'Plague Marine w/ blight launcher']) {
    final o = roster.optionsFor(u).firstWhere((x) => x.name == nombre);
    print('== $nombre ==');
    print('   hijos que trae: ${o.children.map((c) => c.name).toList()}');
    print('   grupos que ofrece: ${o.groups.map((g) => g.name).toList()}');
    u.addChild(o);
    for (final of in roster.optionsFor(o)) {
      final cons = of.constraints
          .map((c) => '${c.isMax ? "max" : "min"} ${c.value.round()} (${c.field}/${c.scope})')
          .join(', ');
      print('   ofrece ${of.name}  [${cons.isEmpty ? "sin restricciones" : cons}]');
    }
    print('');
  }
}
