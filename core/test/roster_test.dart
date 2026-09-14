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

  /// Una lista con [copies] copias de la unidad, del tamaño de partida indicado.
  Roster rosterWith(String unitName, int copies, {BattleSize? size}) {
    final unit = deathGuard.units.firstWhere((u) => u.name == unitName);
    final roster = Roster(faction: deathGuard, pointsLimit: 5000)
      ..detachment = dataset.detachmentsOf(deathGuard).first
      ..battleSize = size;
    for (var i = 0; i < copies; i++) {
      roster.add(dataset.selectionFor(unit));
    }
    return roster;
  }

  BattleSize sizeOf(int pointsLimit) =>
      dataset.battleSizes.firstWhere((b) => b.pointsLimit == pointsLimit);

  test('avisa cuando una unidad se repite más veces de las permitidas', () {
    final violations = rosterWith('Poxwalkers', 4, size: sizeOf(2000)).validate();
    expect(violations, isNotEmpty);
    expect(violations.map((v) => v.message).join(' '), contains('máximo 3'));
  });

  test('el tamaño de la partida cambia cuántas veces se puede repetir una unidad', () {
    // El límite que declara el dataset es 3, pero un modifier lo baja a 2 en Incursion. Es la
    // regla de las tres copias escalada por tamaño, y afecta a 4.544 de las 6.149 unidades: sin
    // aplicar el modifier, una lista de 1000 puntos se validaría con los límites de una de 2000.
    expect(rosterWith('Poxwalkers', 3, size: sizeOf(2000)).validate(), isEmpty);

    final incursion = rosterWith('Poxwalkers', 3, size: sizeOf(1000)).validate();
    expect(incursion.map((v) => v.message).join(' '), contains('máximo 2'));
    expect(rosterWith('Poxwalkers', 2, size: sizeOf(1000)).validate(), isEmpty);
  });

  test('sin tamaño de partida el límite no se comprueba, y se dice', () {
    // Contestar «no es Incursion» sin saberlo dejaría puesto el límite de Strike Force en una
    // lista que a lo mejor es de 1000 puntos. Se prefiere no comprobar y avisar de que no se ha
    // comprobado.
    final roster = rosterWith('Poxwalkers', 4);
    expect(roster.validate(), isEmpty);
    expect(roster.uncheckedConstraints, greaterThan(0));
    expect(roster.selectionsWithUncheckedConstraints.map((s) => s.name), contains('Poxwalkers'));
  });

  test('el tipo de lista contesta las condiciones que preguntan por él', () {
    // El máximo de Poxwalkers se dobla en Crusade. La condición es un `instanceOf` sobre el tipo
    // de fuerza, que en general no se sabe evaluar, pero los tipos son cuatro y una lista es de
    // uno: preguntarle a la lista de cuál es tiene respuesta exacta.
    final crusade = dataset.forces.firstWhere((f) => f.name == 'Crusade Force');
    final roster = rosterWith('Poxwalkers', 6, size: sizeOf(2000))..force = crusade;
    expect(roster.validate(), isEmpty, reason: 'en Crusade el máximo se dobla a 6');
    expect(roster.uncheckedConstraints, 0);

    final normal = rosterWith('Poxwalkers', 6, size: sizeOf(2000));
    expect(normal.validate(), isNotEmpty);
  });

  test('el enlace aporta sus propias reglas al grupo compartido', () {
    // «Heavy Weapons [Legends]» es un grupo compartido que usan varios tanques, y cada uno lo
    // ajusta desde su enlace: cuántas armas caben aquí. Resolviendo solo el grupo, todos los
    // tanques se validarían con los mismos límites genéricos.
    final aeldari = dataset.factionNamed('Xenos - Aeldari');
    final scorpion = aeldari.units.firstWhere((u) => u.name == 'Scorpion [Legends]');
    final armas = dataset
        .optionsFor(dataset.selectionFor(scorpion))
        .where((o) => o.groupName == 'Heavy Weapons [Legends]')
        .toList();
    expect(armas, isNotEmpty, reason: 'el grupo llega por enlace, no incrustado');

    final delGrupo = (dataset.node(armas.first.groupId!)!['constraints'] as List).length;
    expect(armas.first.groupConstraints, hasLength(greaterThan(delGrupo)),
        reason: 'las del grupo más las que pone el enlace');
    expect(armas.first.groupModifiers.any((m) =>
        armas.first.groupConstraints.any((c) => c.id == m.field)), isTrue,
        reason: 'y los modifiers que las cambian');
  });

  test('optionsFor ofrece lo que se puede elegir, incluidas las mejoras', () {
    // Una mejora no es un caso aparte: es un grupo más de los que cuelgan de un personaje, y
    // llega por enlace. Sin recorrer los grupos enlazados no habría forma de ofrecerlas.
    final prince = dataset.selectionFor(
        deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
    final opciones = dataset.optionsFor(prince);
    final mejoras = opciones.where((o) => o.groupName == 'Enhancements');
    expect(mejoras, isNotEmpty);
    expect(mejoras.map((o) => o.name), contains('Daemon Weapon of Nurgle'));
    expect(opciones.every((o) => o.name.isNotEmpty), isTrue,
        reason: 'un grupo no es una opción: no debe colarse como tal');
  });

  test('una mejora elegida suma sus puntos y gasta presupuesto de Enhancements', () {
    final prince = dataset.selectionFor(
        deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
    final base = prince.points;
    final mejora = dataset
        .optionsFor(prince)
        .firstWhere((o) => o.name == 'Daemon Weapon of Nurgle');
    prince.addChild(mejora);

    final roster = Roster(faction: deathGuard, pointsLimit: 2000)
      ..battleSize = sizeOf(2000)
      ..detachments.add(dataset.detachmentsOf(deathGuard).first)
      ..add(prince);
    expect(roster.points, base + 10);
    expect(prince.costOf(enhancementsCostTypeId), 1);
  });

  test('el ejército no puede pasarse del presupuesto de Enhancements', () {
    final detachment = dataset
        .detachmentsOf(deathGuard)
        .firstWhere((d) => d.name == 'Virulent Vectorium');
    final mejoras = dataset.enhancementsOf(deathGuard, detachmentId: detachment.id);

    Roster conMejoras(int cuantas, BattleSize size) {
      final roster = Roster(faction: deathGuard, pointsLimit: 3000)..battleSize = size;
      roster.detachments.add(detachment);
      for (var i = 0; i < cuantas; i++) {
        final prince = dataset.selectionFor(
            deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
        prince.addChild(dataset
            .optionsFor(prince)
            .firstWhere((o) => o.name == mejoras[i % mejoras.length].name));
        roster.add(prince);
      }
      return roster;
    }

    bool sePasa(Roster r) =>
        r.validate().any((v) => v.message.toLowerCase().contains('enhancement'));

    // Cuatro fuera de Incursion, dos dentro: lo dice la propia fuerza, no está escrito aquí.
    expect(sePasa(conMejoras(4, sizeOf(3000))), isFalse);
    expect(sePasa(conMejoras(5, sizeOf(3000))), isTrue);
    expect(sePasa(conMejoras(2, sizeOf(1000))), isFalse);
    expect(sePasa(conMejoras(3, sizeOf(1000))), isTrue);
  });

  test('el presupuesto de Detachment Points crece con el tamaño de la partida', () {
    final dos = dataset.detachmentsOf(deathGuard).where((d) => d.detachmentPoints == 2).toList();
    expect(dos, hasLength(greaterThan(1)), reason: 'hacen falta dos de 2 DP para sumar 4');

    bool cabe(BattleSize size) {
      final roster = Roster(faction: deathGuard, pointsLimit: size.pointsLimit)
        ..battleSize = size;
      roster.detachments.addAll(dos.take(2));
      return !roster.validate().any((v) => v.message.contains('hay 4'));
    }

    expect(cabe(sizeOf(3000)), isTrue, reason: 'Onslaught da 4 DP');
    expect(cabe(sizeOf(2000)), isFalse, reason: 'Strike Force da 3');
    expect(cabe(sizeOf(1000)), isFalse, reason: 'Incursion da 2');
  });

  test('los tres tamaños de partida traen su límite de puntos', () {
    expect(dataset.battleSizes.map((b) => b.pointsLimit), [1000, 2000, 3000]);
    expect(dataset.battleSizes.first.name, contains('Incursion'));
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

  test('señala qué selección concreta puede quedarse corta de precio', () {
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)
      ..add(unitNamed('Foetid Bloat-drone'))
      ..add(unitNamed('Poxwalkers'));
    roster.applyModifiers();

    final marcadas = roster.selectionsWithUnresolvedCost.map((s) => s.name).toSet();
    expect(marcadas, contains('Foetid Bloat-drone'));
    expect(marcadas, isNot(contains('Poxwalkers')),
        reason: 'el coste de los Poxwalkers sí se resuelve entero');
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

  test('las 36 facciones resuelven detachments', () {
    final sinDetachments =
        dataset.factions.where((f) => dataset.detachmentsOf(f).isEmpty).map((f) => f.name);
    expect(sinDetachments, isEmpty);
  });

  test('un grupo compartido reparte sus detachments entre las facciones que lo usan', () {
    // Aeldari y Drukhari sacan los suyos del mismo grupo de veinticuatro de la librería. Lo que
    // los separa es un modifier que esconde cada uno según el catálogo principal, así que sin
    // evaluarlo los Aeldari saldrían a jugar con detachments Drukhari.
    final aeldari = dataset.factionNamed('Xenos - Aeldari');
    final drukhari = dataset.factionNamed('Xenos - Drukhari');
    final deAeldari = dataset.detachmentsOf(aeldari).map((d) => d.name).toSet();
    final deDrukhari = dataset.detachmentsOf(drukhari).map((d) => d.name).toSet();

    expect(deAeldari, contains('Warhost'));
    expect(deDrukhari, contains('Realspace Raiders'));
    expect(deAeldari.intersection(deDrukhari), isEmpty);
    expect(deAeldari.length + deDrukhari.length, 24, reason: 'se reparten el grupo entero');
  });

  test('cada capítulo de Space Marines se queda con los suyos', () {
    final scars = dataset.factionNamed('Imperium - Adeptus Astartes - White Scars');
    final darkAngels = dataset.factionNamed('Imperium - Adeptus Astartes - Dark Angels');
    final deScars = dataset.detachmentsOf(scars).map((d) => d.name).toSet();
    final deDarkAngels = dataset.detachmentsOf(darkAngels).map((d) => d.name).toSet();

    expect(deScars, contains('Gladius Task Force'), reason: 'los del codex los tienen los dos');
    expect(deDarkAngels, contains('Gladius Task Force'));

    expect(deDarkAngels, contains('Inner Circle Task Force'));
    expect(deScars, isNot(contains('Inner Circle Task Force')));
    expect(deScars, contains('Spearpoint Task Force'));
    expect(deDarkAngels, isNot(contains('Spearpoint Task Force')));
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
    // Solo se queda fuera el Contagion Engines de la Death Guard.
    expect(total - conMejoras, 1);
  });

  test('una lista normal no ofrece detachments de Boarding Actions', () {
    // El dataset mete los dos modos en el mismo grupo. Los quince de Boarding Actions no llevan
    // mejoras y no se pueden jugar en una partida normal, así que ahí no tienen que salir.
    expect(dataset.node(Dataset.boardingActionsCategoryId)?['name'], 'Boarding Actions',
        reason: 'si upstream cambia el identificador, el filtro deja de filtrar en silencio');

    final orkos = dataset.factionNamed('Xenos - Orks');
    final normales = dataset.detachmentsOf(orkos).map((d) => d.name).toSet();
    final abordaje = dataset.detachmentsOf(orkos, boardingActions: true).map((d) => d.name).toSet();

    expect(normales, contains('Green Tide'));
    expect(normales, isNot(contains('Ramship Raiders')));
    expect(abordaje, contains('Ramship Raiders'));
    expect(normales.intersection(abordaje), isEmpty);

    final todosAbordaje = dataset.factions
        .expand((f) => dataset.detachmentsOf(f, boardingActions: true))
        .length;
    expect(todosAbordaje, 15);
  });

  test('los detachments de tamaño completo dan sus cuatro mejoras', () {
    // El dataset gradúa los detachments por Detachment Points: los de 2 y 3 son los de una
    // partida normal y llevan cuatro mejoras, y los de 1 son los pequeños, que llevan una o dos.
    // Sobre los completos la resolución tiene que ser exacta, no aproximada.
    const detachmentPointsCostTypeId = '82ae-1066-5107-6ae0';
    var completos = 0, conCuatro = 0;
    for (final faction in dataset.factions) {
      for (final detachment in dataset.detachmentsOf(faction)) {
        final costs = dataset.node(detachment.id)!['costs'] as List? ?? const [];
        final points = costs
            .cast<Map<String, dynamic>>()
            .where((c) => c['typeId'] == detachmentPointsCostTypeId)
            .map((c) => ((c['value'] as num?) ?? 0).round());
        if (points.isEmpty || points.first < 2) continue;
        completos++;
        if (dataset.enhancementsOf(faction, detachmentId: detachment.id).length == 4) {
          conCuatro++;
        }
      }
    }
    expect(completos, greaterThan(300));
    expect(conCuatro / completos, greaterThan(0.99));
  });
}
