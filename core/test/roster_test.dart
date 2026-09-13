import 'dart:io';

import 'package:test/test.dart';
import 'package:warorgan_core/warorgan_core.dart';

Directory _datasetDirectory() {
  final spanish = Directory('../data/bsdata-es');
  return spanish.existsSync() ? spanish : Directory('../data/bsdata');
}

void main() {
  late Dataset dataset;
  late Faction deathGuard;

  setUpAll(() async {
    dataset = await Dataset.load(_datasetDirectory());
    deathGuard = dataset.factionNamed('Chaos - Death Guard');
  });

  Selection unitNamed(String name) =>
      dataset.selectionFor(deathGuard.units.firstWhere((u) => u.name == name));

  test('la selección de partida despliega los mínimos que exige la unidad', () {
    final poxwalkers = unitNamed('Poxwalkers');
    final models = poxwalkers.children.where((c) => c.type == 'model');
    expect(models, hasLength(1));
    expect(models.first.count, 10, reason: 'el grupo obliga a un mínimo de diez');
    expect(poxwalkers.points, 65);
  });

  test('suma el coste que la unidad deja en su miniatura', () {
    expect(unitNamed('Myphitic Blight-hauler').points, 95);
  });

  test('el coste de la lista es la suma de lo seleccionado', () {
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)
      ..add(unitNamed('Poxwalkers'))
      ..add(unitNamed('Myphitic Blight-hauler'));
    expect(roster.points, 160);
    expect(roster.pointsRemaining, 840);
    expect(roster.validate(), isEmpty);
  });

  test('avisa cuando la lista se pasa del límite de puntos', () {
    final roster = Roster(faction: deathGuard, pointsLimit: 100)..add(unitNamed('Poxwalkers'))
      ..add(unitNamed('Myphitic Blight-hauler'));
    final violations = roster.validate();
    expect(violations, hasLength(1));
    expect(violations.first.message, contains('160 puntos y el límite es 100'));
  });

  test('avisa cuando un grupo se queda por debajo de su mínimo', () {
    final poxwalkers = unitNamed('Poxwalkers');
    poxwalkers.children.firstWhere((c) => c.type == 'model').count = 5;
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)..add(poxwalkers);
    final violations = roster.validate();
    expect(violations, isNotEmpty);
    expect(violations.map((v) => v.message).join(' '), contains('mínimo 10'));
  });

  test('avisa cuando una unidad se repite más veces de las permitidas', () {
    final unit = deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers');
    final limit = unit.constraints.firstWhere(
        (c) => c.isMax && c.field == 'selections' && c.scope == 'force');
    final roster = Roster(faction: deathGuard, pointsLimit: 5000);
    for (var i = 0; i <= limit.value; i++) {
      roster.add(dataset.selectionFor(unit));
    }
    final violations = roster.validate();
    expect(violations, isNotEmpty);
    expect(violations.map((v) => v.message).join(' '), contains('máximo ${limit.value}'));
  });

  test('cualquier unidad de cualquier facción se puede seleccionar sin romperse', () {
    // Recorre las 36 facciones: es lo que descarta ciclos de enlaces y entradas mal formadas.
    var built = 0;
    for (final faction in dataset.factions) {
      for (final unit in faction.units) {
        final selection = dataset.selectionFor(unit);
        expect(selection.name, isNotEmpty, reason: '${faction.name} · ${unit.name}');
        expect(selection.points, greaterThanOrEqualTo(0));
        built++;
      }
    }
    expect(built, greaterThan(6000));
  });
}
