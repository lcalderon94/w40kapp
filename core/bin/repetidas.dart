// Comprueba el precio de las copias repetidas contra lo que dice el Munitorum Field Manual.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  final dg = dataset.factionNamed('Chaos - Death Guard');
  for (final nombre in ['Plagueburst Crawler', 'Great Unclean One', 'Defiler', 'Chaos Land Raider']) {
    final roster = Roster(faction: dg, pointsLimit: 3000)
      ..detachments.add(dataset.detachmentsOf(dg).first);
    final u = dg.units.where((x) => x.name == nombre).firstOrNull;
    if (u == null) { print('$nombre: no está en Death Guard'); continue; }
    final precios = <int>[];
    for (var i = 0; i < 4; i++) {
      roster.add(roster.selectionFor(u));
      roster.applyModifiers();
      precios.add(roster.points);
    }
    final sueltos = [
      for (var i = 0; i < precios.length; i++)
        i == 0 ? precios[0] : precios[i] - precios[i - 1]
    ];
    print('${nombre.padRight(24)} copias 1ª-4ª: ${sueltos.join(' · ')}');
  }
}
