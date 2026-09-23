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
    dataset = await Dataset.load(_datasetDirectory(), notas: File('../data/wargear/notas-de-equipo.json'));
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

  group('qué unidades puede ofrecer una lista', () {
    Roster conDetachment(String nombre) => Roster(faction: deathGuard, pointsLimit: 2000)
      ..battleSize = sizeOf(2000)
      ..detachments.add(dataset.detachmentsOf(deathGuard).firstWhere((d) => d.name == nombre));

    test('el detachment decide qué unidades hay, en TODAS las facciones', () {
      // El barrido que había que hacer desde el principio, en vez de arreglar Death Guard y dar
      // el resto por bueno. 29 facciones atan unidades a un detachment, y son 301 casos: los
      // demonios de cada dios en las cuatro legiones del Caos, los Ynnari de Aeldari, los aliados
      // Tyránidos de Genestealer Cults, los cultistas de Chaos Knights, los Corsarios de Drukhari.
      //
      // No se da por hecho en qué dirección va el gate: el dataset lo usa para **enseñar** unidades
      // (los demonios con Tallyband Summoners) y también para **esconderlas** (los Corsarios con
      // Reaper's Wager). Lo que se exige es que elegir ese detachment cambie lo que se ofrece.
      var comprobados = 0;
      final mudos = <String>[];

      for (final faction in dataset.factions) {
        final detachments = dataset.detachmentsOf(faction);
        if (detachments.length < 2) continue;
        final options = dataset.visibilityOptionsOf(faction).map((o) => o.id).toList();
        final byId = {for (final d in detachments) d.id: d.name};

        final gated = <String, Set<String>>{};
        for (final unit in faction.units) {
          for (final modifier in unit.visibility) {
            for (final condition in modifier.allConditions) {
              if (byId.containsKey(condition.childId)) {
                gated.putIfAbsent(unit.name, () => {}).add(byId[condition.childId]!);
              }
            }
          }
        }
        if (gated.isEmpty) continue;

        final visibleWith = <String, Set<String>>{};
        for (final detachment in detachments) {
          final roster = Roster(faction: faction, pointsLimit: 2000)
            ..battleSize = sizeOf(2000)
            ..detachments.add(detachment);
          roster.shownOptions.addAll(options);
          visibleWith[detachment.name] = roster.availableUnits.map((u) => u.name).toSet();
        }

        gated.forEach((unit, its) {
          comprobados++;
          final conEl = its.map((d) => visibleWith[d]!.contains(unit)).toSet();
          final conOtros = visibleWith.entries
              .where((e) => !its.contains(e.key))
              .map((e) => e.value.contains(unit))
              .toSet();
          final cambia = conOtros.isEmpty ||
              conEl.difference(conOtros).isNotEmpty ||
              conOtros.difference(conEl).isNotEmpty;
          if (!cambia) mudos.add('${faction.name} · \$unit (${its.join(", ")})');
        });
      }

      expect(comprobados, greaterThan(200), reason: 'si baja, el barrido dejó de cubrir casos');
      expect(mudos, isEmpty, reason: 'gates que no surten ningún efecto');
    });

    test('los demonios de Nurgle solo entran con Tallyband Summoners', () {
      // Un caso con nombre del barrido de arriba, para que un fallo se lea de un vistazo.
      const demonios = [
        'Plaguebearers',
        'Nurglings',
        'Great Unclean One',
        'Rotigus',
        'Plague Drones',
        'Beasts of Nurgle',
      ];
      final sinTallyband =
          conDetachment('Virulent Vectorium').availableUnits.map((u) => u.name).toSet();
      final conTallyband =
          conDetachment('Tallyband Summoners').availableUnits.map((u) => u.name).toSet();

      for (final demonio in demonios) {
        expect(deathGuard.units.map((u) => u.name), contains(demonio),
            reason: 'el catálogo sí lo trae');
        expect(sinTallyband, isNot(contains(demonio)));
        expect(conTallyband, contains(demonio));
      }
    });

    test('las unidades Legends no se ofrecen hasta encenderlas', () {
      final roster = conDetachment('Virulent Vectorium');
      expect(roster.availableUnits.where((u) => u.name.contains('[Legends]')), isEmpty);

      final legends = dataset
          .visibilityOptionsOf(deathGuard)
          .firstWhere((o) => o.name == 'Show Legends');
      roster.shownOptions.add(legends.id);
      expect(roster.availableUnits.where((u) => u.name.contains('[Legends]')), isNotEmpty);
    });

    test('cada facción trae sus propios interruptores', () {
      // Cuelgan del enlace de cada catálogo, no de una lista única: Chaos Daemons añade los cuatro
      // dioses y Astra Militarum los Imperial Agents. Buscando en un solo sitio se pierden.
      final daemons = dataset.factionNamed('Chaos - Chaos Daemons');
      final nombres = dataset.visibilityOptionsOf(daemons).map((o) => o.name);
      expect(nombres, contains('Show Nurgle Daemons'));
      expect(nombres, contains('Show Legends'), reason: 'los comunes también');
      expect(dataset.visibilityOptionsOf(deathGuard).map((o) => o.name),
          isNot(contains('Show Nurgle Daemons')),
          reason: 'en Death Guard los demonios no van por interruptor sino por detachment');
    });

    test('la facción contesta casi todas las condiciones de visibilidad', () {
      // Las de ámbito `primary-catalogue` son 2.661 y todas se contestan mirando de qué facción es
      // la lista; antes se daban por no evaluables y no escondían nada. Lo que queda son las que
      // cuentan **fuerzas**, el hueco de siempre.
      var sinEvaluar = 0, conProblema = 0;
      for (final faction in dataset.factions) {
        final detachments = dataset.detachmentsOf(faction);
        if (detachments.isEmpty) continue;
        final roster = Roster(faction: faction, pointsLimit: 2000)
          ..battleSize = sizeOf(2000)
          ..detachments.add(detachments.first);
        roster.availableUnits;
        sinEvaluar += roster.unresolvedVisibility;
        if (roster.unresolvedVisibility > 0) conProblema++;
      }
      expect(conProblema, lessThanOrEqualTo(4), reason: 'y solo en unas pocas facciones');
      expect(sinEvaluar, lessThan(150));
    });

    test('solo se ofrecen las unidades de la facción, no todo el catálogo', () {
      // Un catálogo trae mucho más que su facción: aliados, Legends y fortificaciones. Un ejército
      // de Imperial Knights son sus veintitrés Knights, no las ciento tres entradas del fichero.
      final knights = dataset.factionNamed('Imperium - Imperial Knights');
      final roster = Roster(faction: knights, pointsLimit: 2000)
        ..battleSize = sizeOf(2000)
        ..detachments.add(dataset.detachmentsOf(knights).first);
      final ofrecidas = roster.availableUnits.map((u) => u.name).toList();

      expect(ofrecidas, contains('Knight Paladin'));
      expect(ofrecidas, contains('Armiger Warglaive'));
      expect(ofrecidas, hasLength(lessThan(30)));
      expect(knights.units, hasLength(greaterThan(90)), reason: 'el fichero trae muchas más');

      final titanes = dataset.factionNamed('Imperium - Adeptus Titanicus');
      final deTitanes = Roster(faction: titanes, pointsLimit: 2000)
        ..battleSize = sizeOf(2000)
        ..detachments.add(dataset.detachmentsOf(titanes).first);
      expect(deTitanes.availableUnits.map((u) => u.name), contains('Warlord Titan'));
      expect(deTitanes.availableUnits, hasLength(lessThan(10)));
    });
  });

  group('qué opciones puede elegir una unidad', () {
    test('una opción no se ofrece en una unidad que no cumple su gate', () {
      // El mismo barrido que con las unidades, un nivel más abajo y sobre las 36 facciones. El
      // dataset comparte una lista de armas entre varias unidades y enseña en cada una solo las
      // suyas, con «escondida si ningún ancestro es X». Son 43.846 gates.
      var conGate = 0;
      final fallos = <String>[];

      for (final faction in dataset.factions) {
        final detachments = dataset.detachmentsOf(faction);
        if (detachments.isEmpty) continue;
        final roster = Roster(faction: faction, pointsLimit: 2000)
          ..battleSize = sizeOf(2000)
          ..detachments.add(detachments.first);
        roster.shownOptions
            .addAll(dataset.visibilityOptionsOf(faction).map((o) => o.id));

        for (final unit in roster.availableUnits) {
          final selection = roster.selectionFor(unit);
          final visible = roster.optionsFor(selection).map((o) => o.entryId).toSet();
          // Las de verdad, no las declaradas: un detachment puede dar palabras clave.
          final categories = roster.categoriesOf(selection);
          for (final option in dataset.optionsFor(selection)) {
            final required = <String>[];
            for (final modifier in [...option.groupModifiers, ...option.modifiers]) {
              if (modifier.field != 'hidden' || modifier.value != true) continue;
              for (final condition in modifier.conditions) {
                if (condition.scope == 'ancestor' && condition.type == 'notInstanceOf') {
                  required.add(condition.childId);
                }
              }
            }
            if (required.isEmpty) continue;
            conGate++;
            final cumple =
                required.every((id) => unit.id == id || categories.contains(id));
            if (visible.contains(option.entryId) && !cumple && fallos.length < 5) {
              fallos.add('${faction.name} · ${unit.name} · ${option.name}');
            }
          }
        }
      }
      expect(conGate, greaterThan(40000), reason: 'si baja, el barrido dejó de cubrir casos');
      expect(fallos, isEmpty);
    });

    test('filtrar deja fuera buena parte de lo que el catálogo enchufa', () {
      final deathGuardRoster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..battleSize = sizeOf(2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      var sinFiltrar = 0, filtradas = 0;
      for (final unit in deathGuardRoster.availableUnits) {
        final selection = dataset.selectionFor(unit);
        sinFiltrar += dataset.optionsFor(selection).length;
        filtradas += deathGuardRoster.optionsFor(selection).length;
      }
      expect(filtradas, lessThan(sinFiltrar));
      expect(deathGuardRoster.unresolvedVisibility, 0);
    });
  });

  group('las palabras clave que cambian', () {
    Roster deChaosKnights(String detachment) {
      final knights = dataset.factionNamed('Chaos - Chaos Knights');
      return Roster(faction: knights, pointsLimit: 2000)
        ..battleSize = sizeOf(2000)
        ..detachments.add(
            dataset.detachmentsOf(knights).firstWhere((d) => d.name == detachment));
    }

    const characterId = '9cfd-1c32-585f-7d5c';

    test('un detachment puede convertir una unidad en Character', () {
      // Houndpack Lance mete al War Dog una opción que le da la palabra clave Character, y de eso
      // cuelgan sus cuatro mejoras. Sin aplicar los modifiers de categoría, la unidad nunca es
      // Character y esas mejoras no aparecen en ninguna parte.
      final conHoundpack = deChaosKnights('Houndpack Lance');
      final dog = conHoundpack.selectionFor(
          conHoundpack.availableUnits.firstWhere((u) => u.name == 'War Dog Brigand'));
      expect(conHoundpack.categoriesOf(dog), contains(characterId));
      expect(
          conHoundpack
              .optionsFor(dog)
              .where((o) => o.baseCosts.containsKey(enhancementsCostTypeId)),
          hasLength(4));
    });

    test('y con otro detachment no lo es, ni recibe esas mejoras', () {
      final otro = deChaosKnights('Traitoris Lance');
      final dog = otro.selectionFor(
          otro.availableUnits.firstWhere((u) => u.name == 'War Dog Brigand'));
      expect(otro.categoriesOf(dog), isNot(contains(characterId)));
      expect(
          otro.optionsFor(dog).where((o) => o.baseCosts.containsKey(enhancementsCostTypeId)),
          isEmpty);
    });

    test('la selección de partida no arrastra equipo de otro detachment', () {
      // `Dataset.selectionFor` despliega los mínimos mirando solo el dataset, y ahí entra equipo
      // que depende del detachment. `Roster.selectionFor` lo poda.
      final otro = deChaosKnights('Traitoris Lance');
      final unit = otro.availableUnits.firstWhere((u) => u.name == 'War Dog Brigand');
      expect(dataset.selectionFor(unit).descendantsAndSelf.map((s) => s.name),
          contains('Houndpack Lance Character'));
      expect(otro.selectionFor(unit).descendantsAndSelf.map((s) => s.name),
          isNot(contains('Houndpack Lance Character')));
    });
  });

  test('ninguna mejora de un detachment se ofrece bajo otro', () {
    // La garantía que importa, sobre las 36 facciones y los 547 detachments. Al equipar aparecen
    // también mejoras que **no** son del detachment, y eso es correcto: hay mejoras atadas a una
    // unidad y no a un detachment —el Pennant of Remembrance lo lleva cualquier Ancient, el Lancet
    // of the Worldsore solo un Helbrute—. Lo que no puede pasar es que una mejora **con** gate de
    // detachment salga con otro distinto.
    final detachmentIds = <String>{};
    for (final faction in dataset.factions) {
      for (final d in dataset.detachmentsOf(faction)) {
        detachmentIds.add(d.id);
      }
      for (final d in dataset.detachmentsOf(faction, boardingActions: true)) {
        detachmentIds.add(d.id);
      }
    }

    var comprobadas = 0;
    final coladas = <String>[];
    for (final faction in dataset.factions) {
      for (final detachment in dataset.detachmentsOf(faction)) {
        final suyas = dataset
            .enhancementsOf(faction, detachmentId: detachment.id)
            .map((e) => e.name)
            .toSet();
        final roster = Roster(faction: faction, pointsLimit: 2000)
          ..battleSize = sizeOf(2000)
          ..detachments.add(detachment);
        roster.shownOptions
            .addAll(dataset.visibilityOptionsOf(faction).map((o) => o.id));

        for (final unit in roster.availableUnits) {
          for (final option in roster.optionsFor(roster.selectionFor(unit))) {
            if (!option.baseCosts.containsKey(enhancementsCostTypeId)) continue;
            if (suyas.contains(option.name)) continue;
            comprobadas++;
            final node = dataset.node(option.entryId);
            final atadaAUnDetachment = node != null &&
                Modifier.allOf(node).any((m) =>
                    m.field == 'hidden' &&
                    m.allConditions.any((c) => detachmentIds.contains(c.childId)));
            if (atadaAUnDetachment && coladas.length < 5) {
              coladas.add('${faction.name} · ${detachment.name} · ${option.name}');
            }
          }
        }
      }
    }
    expect(comprobadas, greaterThan(900), reason: 'si baja, el barrido dejó de cubrir casos');
    expect(coladas, isEmpty);
  });

  test('los gates de las mejoras van todos en el mismo sentido', () {
    // Lo que justifica cómo se atribuyen: `enhancementsOf` recoge los detachments que nombran las
    // condiciones de `hidden` de una mejora y se la da a ese detachment. Eso solo vale si el gate
    // siempre **habilita**. Se comprobó sobre el dataset entero: los 315 son «lessThan 1» o
    // «equalTo 0», o sea «escondida si NO llevas ese detachment». Ninguno al revés. Si upstream
    // mete uno invertido, este test salta y hay que dejar de usar el atajo.
    final detachmentIds = <String>{};
    for (final faction in dataset.factions) {
      for (final detachment in dataset.detachmentsOf(faction)) {
        detachmentIds.add(detachment.id);
      }
      for (final detachment in dataset.detachmentsOf(faction, boardingActions: true)) {
        detachmentIds.add(detachment.id);
      }
    }

    var comprobados = 0;
    final invertidos = <String>[];
    for (final faction in dataset.factions) {
      for (final detachment in dataset.detachmentsOf(faction)) {
        for (final enhancement in dataset.enhancementsOf(faction, detachmentId: detachment.id)) {
          final node = dataset.node(enhancement.id)!;
          for (final modifier in Modifier.allOf(node)) {
            if (modifier.field != 'hidden' || modifier.value != true) continue;
            for (final condition in modifier.allConditions) {
              if (!detachmentIds.contains(condition.childId)) continue;
              comprobados++;
              final habilita = (condition.type == 'lessThan' && condition.value == 1) ||
                  (condition.type == 'equalTo' && condition.value == 0);
              if (!habilita) {
                invertidos.add('${enhancement.name}: ${condition.type} ${condition.value}');
              }
            }
          }
        }
      }
    }
    expect(comprobados, greaterThan(100));
    expect(invertidos, isEmpty);
  });

  test('un grupo vacío incumple su mínimo, y se dice', () {
    // Los Blightlord Terminators exigen entre 2 y 9 miniaturas de su grupo. Ahora la unidad llega
    // con las suyas puestas, así que para probar el caso hay que vaciarlo a mano: es lo que pasa
    // en cuanto el jugador quita miniaturas. Mirando solo los grupos que ya tienen algo dentro, el
    // que incumple —el vacío— era justo el que no se comprobaba, y la lista salía legal.
    final unidad = deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators');
    final roster = Roster(faction: deathGuard, pointsLimit: 2000)
      ..battleSize = sizeOf(2000)
      ..detachments.add(dataset.detachmentsOf(deathGuard).first);
    final puesta = dataset.selectionFor(unidad);
    roster.add(puesta);

    final grupo = puesta.groups.firstWhere((g) => g.name == '2-9 Blightlord Terminators');
    puesta.children.removeWhere((c) => c.groupId == grupo.id);

    expect(roster.validate().map((v) => v.message).join(' '), contains('mínimo 2, hay 0'));
  });

  test('un grupo obligatorio con una sola opción se rellena solo', () {
    // Si no hay nada que elegir, no se hace elegir: la unidad nacería incumpliendo por algo que el
    // jugador no podía decidir de otra manera.
    var conUnaSolaOpcion = 0;
    for (final unidad in deathGuard.units) {
      final seleccion = dataset.selectionFor(unidad);
      for (final grupo in seleccion.groups) {
        final opciones = dataset
            .optionsFor(seleccion)
            .where((o) => o.groupId == grupo.id)
            .length;
        final minimo = grupo.constraints
            .where((c) => c.type == 'min' && c.field == 'selections' && c.value > 0);
        if (opciones != 1 || minimo.isEmpty) continue;
        conUnaSolaOpcion++;
        final puestas = seleccion.children
            .where((h) => h.groupId == grupo.id)
            .fold(0, (t, h) => t + h.count);
        expect(puestas, greaterThanOrEqualTo(minimo.first.value.round()),
            reason: '${unidad.name} · ${grupo.name}');
      }
    }
    expect(conUnaSolaOpcion, greaterThan(0), reason: 'si no hay casos, el test no prueba nada');
  });

  test('una lista de partida normal no ofrece nada de Crusade', () {
    // El dataset mete el material de Crusade en todas las unidades y no lo marca de ninguna
    // manera: ni lo esconde, ni lo mete en una categoría, ni lo ata al tipo de fuerza. Sin
    // filtrarlo, equipar una unidad enseña «Battle Tallies» y «Weapon Modifications», y sus
    // mínimos salen como incumplimientos de una lista que es perfectamente legal.
    final unidad = deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators');
    final seleccion = dataset.selectionFor(unidad);
    final grupos = dataset.optionsFor(seleccion).map((o) => o.groupName).toSet();

    for (final crusade in Dataset.crusadeGroupNames) {
      expect(grupos, isNot(contains(crusade)));
    }
    expect(dataset.optionsFor(seleccion, crusade: true).map((o) => o.groupName).toSet(),
        contains('Weapon Modifications'),
        reason: 'con crusade: true vuelven, que el dato sigue estando');
  });

  test('lo que se esconde de Crusade no cuesta puntos ni es una mejora', () {
    // Es la comprobación que justifica el criterio: si escondiera algo con precio, estaría
    // quitando decisiones de una lista de partida normal.
    for (final faction in dataset.factions.take(8)) {
      for (final unidad in faction.units) {
        final seleccion = dataset.selectionFor(unidad);
        final normales = dataset.optionsFor(seleccion).map((o) => o.entryId).toSet();
        for (final opcion in dataset.optionsFor(seleccion, crusade: true)) {
          if (normales.contains(opcion.entryId)) continue;
          expect(opcion.basePointsEach, 0, reason: '${unidad.name} · ${opcion.name}');
          expect(opcion.baseCosts.containsKey(enhancementsCostTypeId), isFalse,
              reason: '${unidad.name} · ${opcion.name}');
        }
      }
    }
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

  test('la copia repetida de una unidad cuesta lo que dice el manual', () {
    // En 11ª el precio sube con las copias, y el dataset lo escribe con localConditionGroups:
    // «cuenta las que van antes que yo y son de esta hoja de datos». Contrastado con el Munitorum
    // Field Manual v1.4: el Plagueburst Crawler vale 170 la primera y 200 de la segunda en
    // adelante; el Great Unclean One, 265 las dos primeras y 280 de la tercera.
    List<int> copias(String nombre, int cuantas) {
      final roster = Roster(faction: deathGuard, pointsLimit: 3000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final sueltos = <int>[];
      var antes = 0;
      for (var i = 0; i < cuantas; i++) {
        roster.add(roster.selectionFor(
            deathGuard.units.firstWhere((u) => u.name == nombre)));
        roster.applyModifiers();
        sueltos.add(roster.points - antes);
        antes = roster.points;
      }
      return sueltos;
    }

    expect(copias('Plagueburst Crawler', 3), [170, 200, 200]);
    expect(copias('Great Unclean One', 3), [265, 265, 280]);
  });

  test('ya no queda ningún modifier de coste sin evaluar en todo el dataset', () {
    // Eran 1.390, el 22,6 % de las unidades, y todos eran localConditionGroups. Si upstream mete
    // una construcción nueva que el motor no entienda, esto lo canta en vez de dejar precios
    // cortos en silencio.
    var omitidos = 0;
    for (final faccion in dataset.factions) {
      final detachments = dataset.detachmentsOf(faccion);
      if (detachments.isEmpty) continue;
      final roster = Roster(faction: faccion, pointsLimit: 3000)
        ..detachments.add(detachments.first);
      for (final unidad in faccion.units) {
        roster.units
          ..clear()
          ..add(roster.selectionFor(unidad));
        roster.applyModifiers();
        omitidos += roster.skippedModifiers;
      }
    }
    expect(omitidos, 0);
  });

  test('lo que se deja sin evaluar se puede señalar, y ahora no hay nada que señalar', () {
    // Antes el Foetid Bloat-drone salía marcado: su precio dependía de un localConditionGroup sin
    // implementar. Ya se evalúa, así que la marca tiene que estar vacía —y las dos formas de
    // contarlo, el total y las selecciones concretas, tienen que decir lo mismo. Si upstream trae
    // algo que el motor no entienda, volverán a llenarse las dos a la vez.
    final roster = Roster(faction: deathGuard, pointsLimit: 1000)
      ..detachments.add(dataset.detachmentsOf(deathGuard).first)
      ..add(unitNamed('Foetid Bloat-drone'))
      ..add(unitNamed('Poxwalkers'));
    roster.applyModifiers();

    expect(roster.skippedModifiers, 0);
    expect(roster.selectionsWithUnresolvedCost, isEmpty);
    expect(roster.skippedModifiers == 0, roster.selectionsWithUnresolvedCost.isEmpty,
        reason: 'el total y el detalle tienen que contar lo mismo');
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

  group('unir líderes a unidades', () {
    // Todo sale de las asociaciones de BSData: a quién se une cada personaje lo dicen sus
    // `associations`, y cuántos caben en cada unidad sus restricciones de campo `associations`
    // con los modifiers que las cambian. Nada se lee del texto de las hojas.
    Roster lista(String faccion, [List<String> detachments = const []]) {
      final f = dataset.factionNamed(faccion);
      final todos = dataset.detachmentsOf(f);
      return Roster(faction: f, pointsLimit: 2000)
        ..detachments.addAll(detachments.isEmpty
            ? [todos.first]
            : [for (final d in detachments) todos.firstWhere((x) => x.name == d)]);
    }

    Selection poner(Roster roster, String nombre) {
      final s = roster.selectionFor(roster.faction.units.firstWhere((u) => u.name == nombre));
      roster.add(s);
      return s;
    }

    test('un líder solo se une a las unidades que declaran sus asociaciones', () {
      final roster = lista('Chaos - Death Guard');
      final marines = poner(roster, 'Plague Marines');
      final lord = poner(roster, 'Lord of Virulence');
      expect(roster.hostsFor(lord), isNot(contains(marines)));

      final blight = poner(roster, 'Blightlord Terminators');
      expect(roster.hostsFor(lord), contains(blight));
      expect(roster.attach(lord, blight), isNull);
      expect(roster.leadersOn(blight), contains(lord));

      // Un segundo Leader ya no cabe: Blightlord Terminators declara «máximo 1 Leader». Se sigue
      // ofreciendo, con el motivo, para que el jugador sepa por qué no.
      final otro = poner(roster, 'Lord of Contagion');
      expect(roster.hostsFor(otro), contains(blight));
      expect(roster.motivoParaUnir(otro, blight), 'Blightlord Terminators ya lleva 1 de 1 Leader');
      expect(roster.attach(otro, blight), isNotNull);
      expect(otro.attachedTo, isNull);
    });

    test('Plague Marines: Plaguecaster sí, Biologus de segundo sí, Foul Blightspawn de tercero no',
        () {
      final roster = lista('Chaos - Death Guard');
      final marines = poner(roster, 'Plague Marines');
      final plaguecaster = poner(roster, 'Malignant Plaguecaster');
      final biologus = poner(roster, 'Biologus Putrifier');
      final blightspawn = poner(roster, 'Foul Blightspawn');

      expect(roster.attach(plaguecaster, marines), isNull);
      // El modifier de la escuadra sube su límite de 1 a 2 porque el que entra es un Biologus.
      expect(roster.attach(biologus, marines), isNull);
      expect(roster.motivoParaUnir(blightspawn, marines), 'Plague Marines ya lleva 2 de 2 Leader');
      expect(roster.validate().where((v) => v.selection == marines), isEmpty);
    });

    test('dos Plaguecasters en la misma escuadra no', () {
      final roster = lista('Chaos - Death Guard');
      final marines = poner(roster, 'Plague Marines');
      final uno = poner(roster, 'Malignant Plaguecaster');
      final otro = poner(roster, 'Malignant Plaguecaster');
      expect(roster.attach(uno, marines), isNull);
      expect(roster.motivoParaUnir(otro, marines), 'Plague Marines ya lleva 1 de 1 Leader');
    });

    test('el Biologus no lidera Poxwalkers y el Plaguecaster sí', () {
      final roster = lista('Chaos - Death Guard');
      final pox = poner(roster, 'Poxwalkers');
      final biologus = poner(roster, 'Biologus Putrifier');
      final plaguecaster = poner(roster, 'Malignant Plaguecaster');
      expect(roster.hostsFor(biologus), isNot(contains(pox)));
      expect(roster.hostsFor(plaguecaster), contains(pox));
    });

    test('una unidad unida solo lleva una mejora, contando las de todos sus personajes', () {
      final roster = lista('Chaos - Death Guard', ['Paragons of Putrescence']);
      final marines = poner(roster, 'Plague Marines');
      final plaguecaster = poner(roster, 'Malignant Plaguecaster');
      final biologus = poner(roster, 'Biologus Putrifier');
      void mejora(Selection s, String nombre) =>
          s.addChild(roster.optionsFor(s).firstWhere((o) => o.name == nombre));
      mejora(plaguecaster, 'Host of the Hybridised Pox');
      mejora(biologus, 'Rejuvenating Swarm');

      expect(roster.attach(plaguecaster, marines), isNull);
      expect(roster.motivoParaUnir(biologus, marines),
          'Una unidad adjunta solo puede llevar 1 mejora');
    });

    test('Black Templars: el Castellan apoya y un segundo apoyo ya no cabe', () {
      final roster = lista('Imperium - Adeptus Astartes - Black Templars');
      final escuadra = poner(roster, 'Crusader Squad');
      final castellan = poner(roster, 'Castellan');
      final ancient = poner(roster, 'Crusade Ancient');
      expect(roster.attach(castellan, escuadra), isNull);
      expect(roster.motivoParaUnir(ancient, escuadra), 'Crusader Squad ya lleva 1 de 1 Support');
      expect(roster.validate().where((v) => v.selection == escuadra), isEmpty,
          reason: 'la Crusader Squad nace legal: un Sword Brother, no dos');
    });

    test('un apoyo con min 1 que va suelto se avisa', () {
      final roster = lista('Imperium - Adeptus Astartes - Black Templars');
      final ancient = poner(roster, 'Crusade Ancient');
      expect(roster.validate().where((v) => v.selection == ancient).map((v) => v.message),
          contains('Crusade Ancient tiene que ir unido a una unidad'));
    });

    test('una unidad puede llevar un líder y una unidad de apoyo a la vez', () {
      final roster = lista('Imperium - Adepta Sororitas');
      final escuadra = poner(roster, 'Battle Sisters Squad');
      final canoness = poner(roster, 'Canoness');
      final hospitaller = poner(roster, 'Hospitaller');
      expect(roster.attach(canoness, escuadra), isNull);
      expect(roster.attach(hospitaller, escuadra), isNull);
      expect(roster.leadersOn(escuadra), hasLength(2));
    });

    test('el Judiciar entra como Supporting si el hueco de Leader ya está ocupado', () {
      final roster = lista('Imperium - Adeptus Astartes - Space Marines');
      final escuadra = poner(roster, 'Intercessor Squad');
      final capitan = poner(roster, 'Captain');
      final judiciar = poner(roster, 'Judiciar');
      expect(roster.attach(capitan, escuadra), isNull);
      expect(roster.attach(judiciar, escuadra), isNull);
      final via = dataset
          .joinAssociationsOf(roster.faction.units.firstWhere((u) => u.name == 'Judiciar'))
          .firstWhere((a) => a.id == judiciar.attachedVia);
      expect(via.name, 'Supporting');
      // Y como entra por Supporting, cuenta como Support, no como Leader.
      expect(roster.categoriesOf(judiciar), contains('7dcd-7f61-69a7-0294'));
      expect(roster.validate().where((v) => v.selection == escuadra), isEmpty);
    });

    test('Kroot Carnivores: un Leader con diez, dos con veinte', () {
      final roster = lista("Xenos - T'au Empire");
      final kroot = poner(roster, 'Kroot Carnivores');
      final uno = poner(roster, 'Kroot Flesh Shaper');
      final otro = poner(roster, 'Kroot War Shaper');
      expect(roster.attach(uno, kroot), isNull);
      expect(roster.motivoParaUnir(otro, kroot), 'Kroot Carnivores ya lleva 1 de 1 Leader');

      final grupo = roster.mainModelGroup(kroot)!;
      kroot.puestaDe(roster.defaultOptionFor(kroot, grupo)!)!.count += 10;
      expect(roster.squadTally(kroot, grupo).puestas, 20);
      expect(roster.attach(otro, kroot), isNull);

      // Y si la escuadra vuelve a diez, la lista lo avisa.
      kroot.puestaDe(roster.defaultOptionFor(kroot, grupo)!)!.count -= 10;
      expect(roster.validate().where((v) => v.selection == kroot), isNotEmpty);
    });

    test('quitar la unidad anfitriona separa a su líder en vez de dejarlo colgando', () {
      final roster = lista('Chaos - Death Guard');
      final blight = poner(roster, 'Blightlord Terminators');
      final lord = poner(roster, 'Lord of Virulence');
      roster.attach(lord, blight);
      roster.remove(blight);
      expect(lord.attachedTo, isNull);
      expect(lord.attachedVia, isNull);
    });

    test('la unión guardada vuelve con la asociación por la que entró', () {
      final roster = lista('Imperium - Adeptus Astartes - Space Marines');
      final escuadra = poner(roster, 'Intercessor Squad');
      final capitan = poner(roster, 'Captain');
      final judiciar = poner(roster, 'Judiciar');
      roster..attach(capitan, escuadra)..attach(judiciar, escuadra);

      final vuelta = Guardado.deTexto(dataset, Guardado.aTexto(roster)).roster;
      expect(vuelta.units[2].attachedTo, same(vuelta.units[0]));
      expect(vuelta.units[2].attachedVia, judiciar.attachedVia);
    });

    test('los personajes resuelven a quién unirse en todas las facciones', () {
      var conAnfitriona = 0;
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 5000)
          ..detachments.add(dataset.detachmentsOf(faccion).first);
        final nombres = <String>{};
        final puestas = <Selection>[];
        for (final u in faccion.units) {
          if (!nombres.add(u.name)) continue;
          final s = roster.selectionFor(u);
          roster.add(s);
          puestas.add(s);
        }
        for (final s in puestas) {
          if (roster.hostsFor(s).isNotEmpty) conAnfitriona++;
        }
      }
      expect(conAnfitriona, greaterThan(1000),
          reason: 'si esto se desploma, BSData ha cambiado cómo escribe las asociaciones');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('montar una unidad entera', () {
    test('un modelo trae el arma que le exige el enlace, no solo la que exige el destino', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final marines = roster.selectionFor(
          deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      roster.add(marines);

      // La Plasma gun lleva su `min 1` en el enlace y la Blight launcher en el destino. Mirando
      // solo el destino, el marine de plasma nacía desarmado y el otro no.
      for (final (modelo, arma) in [
        ('Plague Marine w/ plasma gun', 'Plasma gun'),
        ('Plague Marine w/ blight launcher', 'Blight launcher'),
      ]) {
        final puesto = roster.optionsFor(marines).firstWhere((o) => o.name == modelo);
        expect(puesto.children.map((c) => c.name), contains(arma),
            reason: '$modelo tiene que nacer con su $arma puesta');
      }
    });

    test('ninguna unidad de ninguna facción nace con equipo obligatorio sin poner', () {
      var sueltas = 0;
      final culpables = <String>[];
      for (final faccion in dataset.factions) {
        final detachments = dataset.detachmentsOf(faccion);
        if (detachments.isEmpty) continue;
        final roster = Roster(faction: faccion, pointsLimit: 2000)
          ..detachments.add(detachments.first);
        for (final unidad in faccion.units) {
          final s = roster.selectionFor(unidad);
          for (final nodo in s.descendantsAndSelf.toList()) {
            for (final o in roster.optionsFor(nodo)) {
              final minimo = o.constraints
                  .where((c) => !c.isMax && c.field == 'selections')
                  .fold<int>(0, (m, c) => c.value.round() > m ? c.value.round() : m);
              if (minimo < 1) continue;
              final puestas = nodo.children
                  .where((h) => h.entryId == o.entryId)
                  .fold<int>(0, (t, h) => t + h.count);
              if (puestas >= minimo) continue;
              // Si su grupo ya está lleno, no cabe: el dataset pide tres piezas obligatorias en un
              // grupo de dos y no hay forma de cumplir las dos cosas. Eso es del dato, no del
              // motor, y son tres unidades Legends de las 6.149.
              // Se miran el grupo y los que lo contienen: aquí «Ranged weapons» está a 0 de 1,
              // pero el «Loadout» que lo envuelve ya va lleno a 2 de 2.
              var lleno = false;
              var g = o.groupId == null
                  ? null
                  : nodo.groups.where((x) => x.id == o.groupId).firstOrNull;
              while (g != null) {
                final uso = roster.groupUsage(nodo, g);
                if (uso.maximo != null && uso.puestas >= uso.maximo!) {
                  lleno = true;
                  break;
                }
                g = g.parentId == null
                    ? null
                    : nodo.groups.where((x) => x.id == g!.parentId).firstOrNull;
              }
              if (lleno) continue;
              sueltas++;
              if (culpables.length < 5) {
                culpables.add('${faccion.name} · ${unidad.name} → ${o.name}');
              }
            }
          }
        }
      }
      expect(sueltas, 0, reason: 'quedan piezas obligatorias sin poner: $culpables');
    });

    test('un grupo cuenta también lo que se elige en los subgrupos que anidan en él', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final marines = roster.selectionFor(
          deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      roster.add(marines);
      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');

      // «Wargear» exige exactamente dos armas y no contiene ninguna: las contiene en dos
      // subgrupos de una opción cada uno. Contando solo los hijos directos ve cero siempre.
      final wargear = campeon.groups.firstWhere((g) => g.name == 'Wargear');
      final subgrupos = campeon.groups.where((g) => g.parentId == wargear.id);
      expect(subgrupos, isNotEmpty, reason: 'Wargear tiene que saber qué grupos anidan en él');

      elegirEnGrupo(roster, campeon, 'Boltgun');
      expect(roster.validate().map((v) => v.message), isNot(contains(startsWith('Wargear:'))),
          reason: 'con las dos armas puestas, Wargear ya no incumple');
    });

    test('las unidades llegan con su escuadra completa, en todas las facciones', () {
      // Lo que se espera de un constructor: una escuadra de cinco entra con cinco, y con su
      // equipo puesto. Lo que el dataset no marca de serie se rellena con algo legal —el jugador
      // lo cambia de un toque— porque un hueco obligatorio vacío deja la unidad ilegal desde que
      // entra y obliga a ir a buscarlo.
      for (final (faccion, unidad, minis) in [
        ('Chaos - Death Guard', 'Plague Marines', 5),
        ('Chaos - Death Guard', 'Poxwalkers', 10),
        ('Chaos - Death Guard', 'Blightlord Terminators', 3),
        ('Xenos - Necrons', 'Necron Warriors', 10),
        ('Xenos - Orks', 'Boyz', 10),
        ('Xenos - Tyranids', 'Termagants', 10),
        ('Imperium - Astra Militarum', 'Cadian Shock Troops', 10),
      ]) {
        final f = dataset.factionNamed(faccion);
        final roster = Roster(faction: f, pointsLimit: 3000)
          ..detachments.add(dataset.detachmentsOf(f).first);
        final s = roster.selectionFor(f.units.firstWhere((u) => u.name == unidad));
        roster
          ..units.clear()
          ..add(s);
        final puestas = s.descendantsAndSelf
            .where((x) => x.type == 'model')
            .fold<int>(0, (t, x) => t + x.count);
        expect(puestas, minis, reason: '$unidad debería entrar con $minis miniaturas');
        expect(roster.validate(), isEmpty, reason: '$unidad entra pidiendo algo');
      }
    });

    test('casi ninguna unidad del dataset nace por debajo de un mínimo', () {
      var cortas = 0;
      for (final faccion in dataset.factions) {
        final dets = dataset.detachmentsOf(faccion);
        if (dets.isEmpty) continue;
        final roster = Roster(faction: faccion, pointsLimit: 3000)
          ..detachments.add(dets.first);
        for (final unidad in faccion.units) {
          final s = roster.selectionFor(unidad);
          for (final nodo in s.descendantsAndSelf.toList()) {
            for (final g in nodo.groups) {
              final uso = roster.groupUsage(nodo, g);
              if (uso.minimo != null && uso.puestas < uso.minimo!) {
                cortas++;
                break;
              }
            }
          }
        }
      }
      // Eran 728. Las que quedan son grupos cuyas opciones están todas escondidas en ese
      // detachment, así que no hay nada que poner.
      expect(cortas, lessThan(80));
    });

    test('una unidad recién añadida llega con el equipo de su hoja de datos', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final marines = roster.selectionFor(
          deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      roster.add(marines);

      // Cinco miniaturas: el Campeón y cuatro marines con bólter, que es lo que el dataset marca
      // por defecto. Antes llegaba vacía y había que armarla entera a mano.
      final miniaturas = marines.descendantsAndSelf
          .where((s) => s.type == 'model')
          .fold<int>(0, (t, s) => t + s.count);
      expect(miniaturas, 5);
      expect(marines.children.map((c) => c.name), contains('Plague Marine w/ boltgun'));

      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');
      expect(campeon.children.map((c) => c.name), containsAll(['Plague knives', 'Boltgun']));
      expect(roster.validate(), isEmpty, reason: 'y no pide nada, porque ya viene completa');
    });

    test('no se puede pasar del techo que pone el dataset', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final mortarion =
          roster.selectionFor(deathGuard.units.firstWhere((u) => u.name == 'Mortarion'));
      roster.add(mortarion);

      // Mortarion lleva un Rotwind, y lleva puesto el suyo. No caben veinte.
      final rotwind =
          roster.optionsFor(mortarion).firstWhere((o) => o.name == 'Rotwind');
      expect(roster.canAdd(mortarion, rotwind), isFalse);
    });

    test('la escuadra que pidió el usuario sale legal: 10 miniaturas, 180 puntos, sin avisos', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      final marines = roster.selectionFor(
          deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      roster.add(marines);

      // La escuadra llega con cuatro marines de bólter puestos, que es su equipo de serie. Para
      // montar otra cosa hay que quitarlos, igual que en la pantalla se baja su contador a cero.
      marines.children.removeWhere((c) => c.name == 'Plague Marine w/ boltgun');

      poner(roster, marines, 'Plague Marine w/ blight launcher', 2);
      poner(roster, marines, 'Plague Marine w/ plasma gun', 2);
      poner(roster, marines, 'Plague Marine w/ plague spewer', 2);
      poner(roster, marines, 'Plague Marine w/ heavy plague weapon', 3);

      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');
      elegirEnGrupo(roster, campeon, 'Power fist');
      elegirEnGrupo(roster, campeon, 'Plasma gun');

      final miniaturas = marines.descendantsAndSelf
          .where((s) => s.type == 'model')
          .fold<int>(0, (t, s) => t + s.count);
      expect(miniaturas, 10);
      expect(roster.points, 180, reason: 'diez Plague Marines valen 180, no el precio de cinco');
      expect(roster.validate(), isEmpty);
    });
  });
}

/// Pone [veces] copias de una opción, como hace la pantalla.
void poner(Roster roster, Selection padre, String nombre, int veces) {
  for (var i = 0; i < veces; i++) {
    final opcion = roster.optionsFor(padre).firstWhere((o) => o.name == nombre);
    final puesta = padre.children.where((h) => h.entryId == opcion.entryId).firstOrNull;
    if (puesta != null) {
      puesta.count++;
    } else {
      padre.addChild(opcion);
    }
  }
}

/// Elige en un grupo que solo deja una: lo nuevo sustituye a lo viejo, no se apila.
void elegirEnGrupo(Roster roster, Selection padre, String nombre) {
  final opcion = roster.optionsFor(padre).firstWhere((o) => o.name == nombre);
  padre.children.removeWhere((h) => h.groupId == opcion.groupId);
  padre.addChild(opcion);
}
