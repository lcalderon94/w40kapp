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

  BattleSize sizeOf(int points) =>
      dataset.battleSizes.firstWhere((b) => b.pointsLimit == points);

  /// Una lista con de todo: detachment, varias unidades, una mejora y equipo elegido.
  Roster listaDeEjemplo() {
    final roster = Roster(faction: deathGuard, pointsLimit: 2000, name: 'Peregrinos')
      ..battleSize = sizeOf(2000)
      ..detachments.add(dataset
          .detachmentsOf(deathGuard)
          .firstWhere((d) => d.name == 'Virulent Vectorium'));
    for (final name in ['Plague Marines', 'Foetid Bloat-drone']) {
      roster.add(roster.selectionFor(
          roster.availableUnits.firstWhere((u) => u.name == name)));
    }
    final prince = roster.selectionFor(
        roster.availableUnits.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
    prince.addChild(roster
        .optionsFor(prince)
        .firstWhere((o) => o.name == 'Daemon Weapon of Nurgle'));
    roster.add(prince);
    return roster;
  }

  group('guardar y recuperar', () {
    test('la lista vuelve igual: puntos, unidades, detachment y equipo', () {
      final original = listaDeEjemplo();
      final vuelta = Guardado.deTexto(dataset, Guardado.aTexto(original));

      expect(vuelta.perdidas, isEmpty);
      expect(vuelta.roster.name, 'Peregrinos');
      expect(vuelta.roster.points, original.points);
      expect(vuelta.roster.units, hasLength(original.units.length));
      expect(vuelta.roster.detachment!.name, 'Virulent Vectorium');
      expect(vuelta.roster.battleSize!.pointsLimit, 2000);
      expect(
          vuelta.roster.units.fold(0, (t, u) => t + u.costOf(enhancementsCostTypeId)), 1,
          reason: 'la mejora elegida sigue puesta');
      expect(Exportar.aTexto(vuelta.roster), Exportar.aTexto(original),
          reason: 'y se ve exactamente igual');
    });

    test('se guardan las decisiones, no los puntos', () {
      // Es lo que permite que una lista de hace tres meses salga con los puntos de hoy en vez de
      // con los de entonces. En lo guardado no puede haber un precio escrito.
      final texto = Guardado.aTexto(listaDeEjemplo());
      expect(texto, isNot(contains('"puntos"')));
      expect(texto, contains('"limite"'), reason: 'el límite sí, que lo elige el jugador');
    });

    test('los interruptores de contenido se guardan', () {
      final roster = listaDeEjemplo();
      final legends = dataset
          .visibilityOptionsOf(deathGuard)
          .firstWhere((o) => o.name == 'Show Legends');
      roster.shownOptions.add(legends.id);

      final vuelta = Guardado.deTexto(dataset, Guardado.aTexto(roster));
      expect(vuelta.roster.shownOptions, contains(legends.id));
      expect(vuelta.roster.availableUnits.where((u) => u.name.contains('[Legends]')),
          isNotEmpty);
    });

    test('una lista sin detachment se recupera sin él, no se inventa uno', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 1000)..battleSize = sizeOf(1000);
      final vuelta = Guardado.deTexto(dataset, Guardado.aTexto(roster));
      expect(vuelta.roster.detachments, isEmpty);
      expect(vuelta.roster.validate().map((v) => v.message),
          contains('Falta elegir un detachment'));
    });

    test('si algo guardado ya no existe, se monta el resto y se dice', () {
      // Pasa cuando upstream refresca el dataset. Devolver una lista distinta sin avisar sería
      // peor que devolverla incompleta diciéndolo.
      final json = Guardado.aJson(listaDeEjemplo());
      (json['unidades'] as List).add({'id': 'no-existe-esta-unidad'});

      final vuelta = Guardado.deJson(dataset, json);
      expect(vuelta.roster.units, hasLength(3), reason: 'las que sí existen se montan');
      expect(vuelta.perdidas, hasLength(1));
    });

    test('una lista de una versión más nueva no se abre a medias', () {
      final json = Guardado.aJson(listaDeEjemplo())..['version'] = Guardado.version + 1;
      expect(() => Guardado.deJson(dataset, json), throwsFormatException);
    });

    test('recuperar aplica las reglas de hoy, no las de cuando se guardó', () {
      // Una lista de Incursion con tres copias de la misma unidad se guarda tal cual, y al
      // recuperarla el motor vuelve a validarla: si el límite dice dos, sale avisando.
      final poxwalkers =
          deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers');
      final roster = Roster(faction: deathGuard, pointsLimit: 1000)
        ..battleSize = sizeOf(1000)
        ..detachments.add(dataset.detachmentsOf(deathGuard).first);
      for (var i = 0; i < 3; i++) {
        roster.add(roster.selectionFor(poxwalkers));
      }

      final vuelta = Guardado.deTexto(dataset, Guardado.aTexto(roster));
      expect(vuelta.roster.validate().map((v) => v.message).join(' '),
          contains('máximo 2'));
    });
  });

  group('exportar', () {
    test('la cabecera dice lo que hay que saber de un vistazo', () {
      final texto = Exportar.aTexto(listaDeEjemplo());
      final lineas = texto.split('\n');
      expect(lineas.first, 'Peregrinos');
      expect(lineas[1], contains('Death Guard'));
      expect(lineas[1], contains('Strike Force'));
      expect(lineas[1], contains('/2000 pts'));
      expect(lineas[2], contains('Virulent Vectorium'));
    });

    test('las unidades van por rol, con su equipo y sus puntos', () {
      final texto = Exportar.aTexto(listaDeEjemplo());
      expect(texto, contains('CHARACTER'));
      expect(texto, contains('Daemon Prince of Nurgle — 205 pts'));
      expect(texto, contains('Daemon Weapon of Nurgle (10 pts)'));
    });

    test('los avisos salen en el texto, para no pasar una lista ilegal por buena', () {
      final roster = Roster(faction: deathGuard, pointsLimit: 100)
        ..battleSize = sizeOf(2000)
        ..add(Roster(faction: deathGuard, pointsLimit: 2000)
            .selectionFor(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers')));
      final texto = Exportar.aTexto(roster);
      expect(texto, contains('AVISOS'));
      expect(texto, contains('Falta elegir un detachment'));
    });

    test('es texto plano, sin nada que se rompa al pegarlo', () {
      final texto = Exportar.aTexto(listaDeEjemplo());
      expect(texto, isNot(contains('**')));
      expect(texto, isNot(contains('^^')));
      expect(texto, isNot(contains('<')));
    });
  });
}
