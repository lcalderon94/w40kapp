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
      ..detachment = dataset.detachmentsOf(deathGuard).first
      ..add(unitNamed('Poxwalkers'))
      ..add(unitNamed('Myphitic Blight-hauler'));
    expect(roster.points, 160);
    expect(roster.pointsRemaining, 840);
    expect(roster.validate(), isEmpty);
  });

  test('avisa cuando la lista se pasa del límite de puntos', () {
    final roster = Roster(faction: deathGuard, pointsLimit: 100)
      ..detachment = dataset.detachmentsOf(deathGuard).first
      ..add(unitNamed('Poxwalkers'))
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

  test('el coste sube al pasar del tamaño mínimo de unidad', () {
    final poxwalkers = unitNamed('Poxwalkers');
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)..add(poxwalkers);
    expect(roster.points, 65, reason: 'diez miniaturas');

    poxwalkers.children.firstWhere((c) => c.type == 'model').count = 20;
    expect(roster.points, 130, reason: 'veinte miniaturas: lo dobla un modifier');

    poxwalkers.children.firstWhere((c) => c.type == 'model').count = 10;
    expect(roster.points, 65, reason: 'y vuelve a bajar al deshacer');
  });

  test('el modifier no se aplica si su condición no se cumple', () {
    final poxwalkers = unitNamed('Poxwalkers');
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)..add(poxwalkers);
    poxwalkers.children.firstWhere((c) => c.type == 'model').count = 11;
    expect(roster.points, 130);
    poxwalkers.children.firstWhere((c) => c.type == 'model').count = 10;
    expect(roster.points, 65);
  });

  test('no aplica los modifiers cuya condición no sabe evaluar', () {
    // El +10 del Foetid Bloat-drone depende de un localConditionGroup, que cuenta instancias
    // repetidas de la misma unidad con comparaciones (`before`, `instanceOf`) que esta capa no
    // implementa. Ante la duda se deja el precio base y se cuenta el modifier omitido, en vez de
    // aplicarlo a ciegas y dar un precio que parece bueno y no lo es.
    final drone = unitNamed('Foetid Bloat-drone');
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)..add(drone);
    expect(roster.points, 100);
    roster.applyModifiers();
    expect(roster.skippedModifiers, greaterThan(0));
  });

  test('cada facción resuelve sus detachments con la regla traducida', () {
    final detachments = dataset.detachmentsOf(deathGuard);
    expect(detachments, hasLength(greaterThan(5)));
    final conRegla = detachments.where((d) => d.rule != null);
    expect(conRegla, isNotEmpty);
    expect(conRegla.first.rule, isNot(contains('Each time')));
  });

  test('una lista sin detachment no es legal', () {
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)..add(unitNamed('Poxwalkers'));
    expect(roster.validate().map((v) => v.message), contains('Falta elegir un detachment'));

    roster.detachment = dataset.detachmentsOf(deathGuard).first;
    expect(roster.validate(), isEmpty);
  });

  test('casi todas las facciones resuelven detachments', () {
    final sinDetachments =
        dataset.factions.where((f) => dataset.detachmentsOf(f).isEmpty).map((f) => f.name);
    // Aeldari y Drukhari los declaran de una forma que aún no se resuelve.
    expect(sinDetachments, hasLength(lessThanOrEqualTo(2)));
  });

  test('un detachment resuelve sus mejoras con el texto traducido', () {
    final detachment =
        dataset.detachmentsOf(deathGuard).firstWhere((d) => d.name == 'Virulent Vectorium');
    final enhancements = dataset.enhancementsOf(deathGuard, detachmentId: detachment.id);
    expect(enhancements, hasLength(4), reason: 'un detachment de 11ª lleva cuatro mejoras');

    final arma = enhancements.firstWhere((e) => e.name == 'Daemon Weapon of Nurgle');
    expect(arma.points, 10);
    expect(arma.description, contains('Cada vez'));
  });

  test('las mejoras de un detachment no se cuelan en otro', () {
    final detachments = dataset.detachmentsOf(deathGuard);
    final porDetachment = {
      for (final d in detachments)
        d.name: dataset.enhancementsOf(deathGuard, detachmentId: d.id).map((e) => e.id).toSet(),
    };
    final conMejoras = porDetachment.entries.where((e) => e.value.isNotEmpty).toList();
    expect(conMejoras, hasLength(greaterThan(4)));
    for (var i = 0; i < conMejoras.length; i++) {
      for (var j = i + 1; j < conMejoras.length; j++) {
        expect(conMejoras[i].value.intersection(conMejoras[j].value), isEmpty,
            reason: '${conMejoras[i].key} y ${conMejoras[j].key} comparten mejoras');
      }
    }
  });

  test('la mayoría de los detachments resuelven sus mejoras', () {
    var conMejoras = 0, total = 0;
    for (final faction in dataset.factions) {
      final cobertura = dataset.enhancementCoverage(faction);
      conMejoras += cobertura.withEnhancements;
      total += cobertura.total;
    }
    // Los 36 que faltan no atan ninguna mejora a su detachment en el dataset.
    expect(conMejoras / total, greaterThan(0.94));
  });
}
