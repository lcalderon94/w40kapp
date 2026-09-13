import 'dart:io';

import 'package:test/test.dart';
import 'package:warorgan_core/warorgan_core.dart';

/// Se prueba contra el dataset en español si está generado, y si no contra el inglés: la
/// estructura es la misma y `apply` no la toca.
Directory _datasetDirectory() {
  final spanish = Directory('../data/bsdata-es');
  return spanish.existsSync() ? spanish : Directory('../data/bsdata');
}

void main() {
  late Dataset dataset;
  final directory = _datasetDirectory();
  final isSpanish = directory.path.endsWith('bsdata-es');

  setUpAll(() async {
    if (!directory.existsSync()) return;
    dataset = await Dataset.load(directory);
  });

  test('indexa los identificadores de todos los ficheros a la vez', () {
    expect(dataset.nodeCount, greaterThan(100000));
    expect(dataset.factions, hasLength(36));
  });

  test('una facción sin unidades propias las hereda de los catálogos que enlaza', () {
    final whiteScars = dataset.factionNamed('Imperium - Adeptus Astartes - White Scars');
    // Sus entradas raíz son mejoras y enhancements: ninguna resuelve a una unidad, así que todas
    // sus unidades llegan por importRootEntries.
    final unidadesPropias = ((whiteScars.node['entryLinks'] as List?) ?? []).where((raw) {
      final destino = dataset.node((raw as Map<String, dynamic>)['targetId'] as String? ?? '');
      return destino != null && (destino['type'] == 'unit' || destino['type'] == 'model');
    }).length;
    // Declara un puñado de unidades propias —sus personajes— y hereda el resto del catálogo de
    // Space Marines. Sin resolver importRootEntries la facción sería injugable.
    expect(unidadesPropias, lessThan(10));
    expect(whiteScars.units.length, greaterThan(unidadesPropias * 5));
    expect(whiteScars.units, hasLength(greaterThan(50)));
  });

  test('resuelve los puntos declarados en la unidad', () {
    final poxwalkers = dataset
        .factionNamed('Chaos - Death Guard')
        .units
        .firstWhere((u) => u.name == 'Poxwalkers');
    expect(poxwalkers.points, 65);
    expect(poxwalkers.role, 'Infantry');
    expect(poxwalkers.keywords, contains('Nurgle'));
  });

  test('resuelve los puntos que la unidad declara en su miniatura', () {
    final blightHauler = dataset
        .factionNamed('Chaos - Death Guard')
        .units
        .firstWhere((u) => u.name == 'Myphitic Blight-hauler');
    expect(blightHauler.points, 95);
  });

  test('las habilidades llegan por enlace, no incrustadas en la unidad', () {
    final unidades = dataset.factionNamed('Chaos - Death Guard').units;
    final conHabilidades = unidades.where((u) => u.abilities.isNotEmpty);
    expect(conHabilidades, isNotEmpty);
    for (final habilidad in conHabilidades.first.abilities) {
      expect(habilidad.description, isNotEmpty);
    }
  });

  test('casi todas las unidades tienen puntos', () {
    final unidades = dataset.factions.expand((f) => f.units).toList();
    final conPuntos = unidades.where((u) => u.points != null).length;
    expect(unidades.length, greaterThan(1000));
    expect(conPuntos / unidades.length, greaterThan(0.95));
  });

  test('el dataset en español no deja texto de reglas en inglés', () {
    if (!isSpanish) return;
    final descripciones = dataset
        .factionNamed('Chaos - Death Guard')
        .units
        .expand((u) => u.abilities)
        .map((p) => p.description!)
        .toList();
    expect(descripciones, isNotEmpty);
    expect(descripciones.where((d) => d.contains('Each time')), isEmpty);
    expect(descripciones.where((d) => d.contains('Cada vez')), isNotEmpty);
  });
}
