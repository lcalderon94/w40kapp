// La lista de una facción en el formato del Munitorum Field Manual: cada hoja de datos con sus
// tramos de precio por número de miniaturas. Sirve para contrastar contra el documento oficial.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main(List<String> args) async {
  final dataset = await Dataset.load(_dir());
  final f = dataset.factionNamed(args[0]);
  final roster = Roster(faction: f, pointsLimit: 3000)
    ..detachments.add(dataset.detachmentsOf(f).first);

  final normales = <(String, List<String>)>[];
  final aparte = <(String, List<String>)>[];

  for (final u in f.units) {
    final s = roster.selectionFor(u);
    final base = s.baseCosts[pointsCostTypeId] ?? 0;

    // Los tramos los declara el propio dataset: «si hay al menos N miniaturas, el precio es X».
    final tramos = <int, int>{};
    for (final m in s.modifiers) {
      if (m.field != pointsCostTypeId || m.type != 'set') continue;
      for (final c in m.conditions) {
        if (c.childId != 'model' || c.type != 'atLeast') continue;
        tramos[c.value.round()] = m.value is num ? (m.value as num).round() : 0;
      }
    }
    final minimo = s.descendantsAndSelf
        .where((x) => x.type == 'model')
        .fold<int>(0, (t, x) => t + x.count);

    final lineas = <String>[];
    if (tramos.isEmpty) {
      lineas.add('${u.name.padRight(50, '.')} $base');
    } else {
      lineas.add(u.name);
      final claves = <int>{if (minimo > 0) minimo, ...tramos.keys}.toList()..sort();
      for (final k in claves) {
        final precio = tramos[k] ?? base;
        lineas.add('     ${'$k'.padLeft(2)} miniaturas${''.padRight(33, '.')} $precio');
      }
    }
    final fuera = u.name.contains('[Legends]') || u.name.contains('[Crucible]');
    (fuera ? aparte : normales).add((u.name, lineas));
  }

  int porNombre((String, List<String>) a, (String, List<String>) b) => a.$1.compareTo(b.$1);
  normales.sort(porNombre);
  aparte.sort(porNombre);

  print('=== ${f.name} ===');
  print('${normales.length} hojas de datos de torneo  ·  ${aparte.length} de Legends/Crucible\n');
  for (final x in normales) {
    for (final l in x.$2) {
      print(l);
    }
  }
  print('\n--- fuera del MFM (Legends y Crucible): ${aparte.length} ---');
}
