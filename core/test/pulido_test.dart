import 'dart:io';

import 'package:test/test.dart';
import 'package:warorgan_core/warorgan_core.dart';

Directory _datasetDirectory() {
  final spanish = Directory('../data/bsdata-es');
  return spanish.existsSync() ? spanish : Directory('../data/bsdata');
}

/// Lo que se arregló después de probar la app de verdad, fijado para que no se vuelva a romper.
///
/// Cada una de estas mide sobre el dataset entero, no sobre una facción: casi todos estos fallos
/// parecían de una unidad concreta y eran del motor, y con un caso suelto no se ve.
void main() {
  late Dataset dataset;

  setUpAll(() async => dataset = await Dataset.load(_datasetDirectory()));

  Roster listaDe(String faccion, {String? detachment}) {
    final f = dataset.factionNamed(faccion);
    final roster = Roster(faction: f, pointsLimit: 2000)
      ..battleSize = dataset.battleSizes.firstWhere((b) => b.pointsLimit == 2000);
    final suyos = dataset.detachmentsOf(f);
    if (suyos.isNotEmpty) {
      roster.detachments.add(detachment == null
          ? suyos.first
          : suyos.firstWhere((d) => d.name == detachment));
    }
    return roster;
  }

  Selection unidadDe(Roster roster, String nombre) =>
      roster.selectionFor(roster.faction.units.firstWhere((u) => u.name == nombre));

  group('la misma opción en dos grupos', () {
    test('marcar una no marca la otra, en las 295 unidades donde pasa', () {
      // El Defiler ofrece el Electroscourge dos veces: para sustituir el lanzamisiles y para
      // sustituir el baleflamer, y es la misma entrada. Contando por entrada a secas, una sola
      // pulsación marcaba las dos casillas.
      final roster = listaDe('Chaos - Death Guard');
      final defiler = unidadDe(roster, 'Defiler');
      final electro = roster
          .optionsFor(defiler)
          .where((o) => o.name == 'Electroscourge')
          .toList();
      expect(electro, hasLength(2), reason: 'la misma entrada en dos grupos');
      expect(electro.first.entryId, electro.last.entryId);
      expect(electro.first.groupId, isNot(electro.last.groupId));

      defiler.children.removeWhere((c) => c.groupId == electro.first.groupId);
      defiler.addChild(electro.first);

      expect(defiler.cuantasDe(electro.first), 1);
      expect(defiler.cuantasDe(electro.last), 0,
          reason: 'el otro grupo sigue con lo suyo, no se marca solo');
    });

    test('pasa en cientos de unidades, así que no vale arreglarlo a mano', () {
      var unidades = 0;
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 2000);
        final suyos = dataset.detachmentsOf(faccion);
        if (suyos.isNotEmpty) roster.detachments.add(suyos.first);
        for (final entrada in faccion.units) {
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          final repetida = unidad.descendantsAndSelf.any((nodo) {
            final grupos = <String, Set<String?>>{};
            for (final o in roster.optionsFor(nodo)) {
              grupos.putIfAbsent(o.entryId, () => {}).add(o.groupId);
            }
            return grupos.values.any((g) => g.length > 1);
          });
          if (repetida) unidades++;
        }
      }
      expect(unidades, greaterThan(200),
          reason: 'si baja de aquí, upstream ha cambiado y conviene volver a medir');
    });
  });

  group('equipo fijo', () {
    test('lo que el dataset exige y no deja repetir no se puede quitar', () {
      // Las Shearing claws del Defiler son `min 1, max 1`: las lleva y punto, no es una elección.
      // Un contador ahí ofrece bajarlas a cero y dejar la unidad ilegal sin haber elegido nada.
      final roster = listaDe('Chaos - Death Guard');
      final defiler = unidadDe(roster, 'Defiler');
      final garras =
          roster.optionsFor(defiler).firstWhere((o) => o.name == 'Shearing claws');

      expect(defiler.cuantasDe(garras), 1);
      expect(roster.isFixed(defiler, garras), isTrue);
      expect(roster.canRemove(defiler, garras), isFalse);
      expect(roster.canAdd(defiler, garras), isFalse);
    });

    test('pero con alternativas en el grupo no hay nada fijo: es lo que hay puesto', () {
      // Mirando solo el mínimo y el máximo se bloqueaban 15.273 opciones de 17.505 que sí eran
      // una elección. Un arma con `min 1, max 1` dentro de un grupo que ofrece otras tres no es
      // equipo fijo: el grupo existe justo para cambiarla.
      var conAlternativaYBloqueada = 0;
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 2000)
          ..battleSize = dataset.battleSizes.firstWhere((b) => b.pointsLimit == 2000);
        final suyos = dataset.detachmentsOf(faccion);
        if (suyos.isNotEmpty) roster.detachments.add(suyos.first);
        for (final entrada in faccion.units) {
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          for (final nodo in unidad.descendantsAndSelf) {
            final ofrecidas = roster.optionsFor(nodo);
            for (final o in ofrecidas) {
              if (o.groupId == null) continue;
              final hermanas = ofrecidas
                  .where((x) => x.groupId == o.groupId && x.entryId != o.entryId)
                  .length;
              if (hermanas == 0) continue;
              if (roster.isFixed(nodo, o, hayAlternativas: true)) {
                conAlternativaYBloqueada++;
              }
            }
          }
        }
      }
      expect(conAlternativaYBloqueada, 0);
    });

    test('lo que sí se elige se sigue pudiendo quitar', () {
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      final lanzador = roster
          .optionsFor(marines)
          .firstWhere((o) => o.name == 'Plague Marine w/ blight launcher');
      marines.addChild(lanzador);
      expect(roster.canRemove(marines, lanzador), isTrue);
    });
  });

  group('aliados', () {
    test('los Chaos Knights no son de la Death Guard', () {
      final roster = listaDe('Chaos - Death Guard');
      final warDog = roster.faction.units
          .firstWhere((u) => u.name == 'Chaos Cerastus Knight Acheron');
      expect(roster.allyOf(warDog), 'Chaos Knights');

      final plagueMarines =
          roster.faction.units.firstWhere((u) => u.name == 'Plague Marines');
      expect(roster.allyOf(plagueMarines), isNull);
    });

    test('pero en una lista de Chaos Knights sí son la facción', () {
      final roster = listaDe('Chaos - Chaos Knights');
      final knight = roster.faction.units
          .firstWhere((u) => u.name == 'Chaos Cerastus Knight Acheron');
      expect(roster.allyOf(knight), isNull,
          reason: 'allí no son aliados: son el ejército');
    });

    test('se reconocen en las 36 facciones, no solo en la que se probó', () {
      var conAliados = 0;
      var unidadesAliadas = 0;
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 2000);
        final suyas = faccion.units.where((u) => roster.allyOf(u) != null).length;
        if (suyas > 0) conAliados++;
        unidadesAliadas += suyas;
      }
      // Todas menos Drukhari, que es la única que no enlaza ningún catálogo ajeno: no tiene
      // aliados que ofrecer y no es que no se reconozcan.
      expect(conAliados, dataset.factions.length - 1);
      expect(
          dataset.factions
              .where((f) => f.units.every((u) =>
                  Roster(faction: f, pointsLimit: 2000).allyOf(u) == null))
              .map((f) => f.name),
          ['Xenos - Drukhari']);
      expect(unidadesAliadas, greaterThan(1500));
    });

    test('las categorías de aliado salen del dataset, no de una lista escrita a mano', () {
      expect(dataset.allyCategories.values,
          containsAll(['Chaos Knights', 'Imperial Agents', 'Imperial Knights']));
    });
  });

  group('la hoja de datos', () {
    test('no lleva las mejoras del detachment, que no son de la unidad', () {
      // Eran 7.565 perfiles de mejora repartidos por 717 unidades: el Daemon Prince of Nurgle
      // tenía 26 de sus 33 perfiles ocupados por mejoras que no llevaba puestas.
      var coladas = 0;
      for (final faccion in dataset.factions) {
        final mejoras = <String>{};
        for (final d in dataset.detachmentsOf(faccion)) {
          for (final m in dataset.enhancementsOf(faccion, detachmentId: d.id)) {
            mejoras.add(m.name);
          }
        }
        for (final unidad in faccion.units) {
          coladas +=
              dataset.sheetOf(unidad).where((p) => mejoras.contains(p.name)).length;
        }
      }
      expect(coladas, lessThan(100), reason: 'antes eran 7.565');
    });

    test('y sigue trayendo las armas: ninguna se ha ido con las mejoras', () {
      var sinArmas = 0;
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          final hoja = dataset.sheetOf(unidad);
          if (hoja.isNotEmpty &&
              hoja.every((p) => !p.typeName.contains('Weapons'))) {
            sinArmas++;
          }
        }
      }
      expect(sinArmas, lessThanOrEqualTo(522),
          reason: 'las que no tienen armas son las que nunca las tuvieron');
    });

    test('dentro de la lista enseña lo que lleva puesto, no todo lo que podría', () {
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      List<String> armas() => dataset
          .sheetOfSelection(marines)
          .where((p) => p.typeName.contains('Weapons'))
          .map((p) => p.name)
          .toList();

      expect(armas(), contains('Boltgun'), reason: 'entra con bólters puestos');

      // Todos: los cuatro marines rasos y el del Campeón, que va un nivel más abajo.
      marines.children.removeWhere((c) => c.name.contains('boltgun'));
      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');
      campeon.children.removeWhere((c) => c.name == 'Boltgun');

      expect(armas(), isNot(contains('Boltgun')),
          reason: 'si los he quitado todos, el bólter no pinta nada en su hoja');
      expect(armas(), contains('Plague knives'), reason: 'lo que sí lleva, sigue');

      // Y la línea de características y las habilidades no dependen de lo elegido.
      expect(dataset.sheetOfSelection(marines).map((p) => p.typeName), contains('Unit'));
    });

    test('lo mismo con un arma que se elige entre varias, en otra facción', () {
      // El ejemplo de los Custodes: el Caladius Grav-tank elige su cañón, y en la hoja tiene que
      // salir el que se ha puesto y no los otros dos.
      final roster = listaDe('Imperium - Adeptus Custodes');
      final tanque = unidadDe(roster, 'Caladius Grav-tank');
      final opciones = roster
          .optionsFor(tanque)
          .where((o) => o.name.toLowerCase().contains('cannon'))
          .toList();
      expect(opciones, isNotEmpty);

      List<String> armas() => dataset
          .sheetOfSelection(tanque)
          .where((p) => p.typeName.contains('Weapons'))
          .map((p) => p.name)
          .toList();

      final elegido = opciones.first;
      tanque.children.removeWhere((c) => c.groupId == elegido.groupId);
      tanque.addChild(elegido);

      final sobrantes = opciones
          .where((o) => o.groupId == elegido.groupId && o.entryId != elegido.entryId)
          .map((o) => o.name);
      for (final otro in sobrantes) {
        expect(armas(), isNot(contains(otro)),
            reason: 'el cañón que no se ha puesto no está en la hoja');
      }
    });
  });

  group('la salvación invulnerable', () {
    test('se lee, y se lee contra qué vale', () {
      Invulnerable? de(String faccion, String unidad) => Invulnerable.of(dataset.sheetOf(
          dataset.factionNamed(faccion).units.firstWhere((u) => u.name == unidad)));

      final rangers = de('Xenos - Aeldari', 'Rangers')!;
      expect(rangers.value, '5+');
      expect(rangers.scope, 'ataques a distancia');

      final banshees = de('Xenos - Aeldari', 'Howling Banshees')!;
      expect(banshees.value, '4+');
      expect(banshees.scope, 'ataques de cuerpo a cuerpo');

      final asterius = de('Chaos - Chaos Knights', 'Chaos Acastus Knight Asterius')!;
      expect(asterius.isConditional, isTrue);
    });

    test('la condicionada no se confunde con la que vale contra todo', () {
      var condicionadas = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          final inv = Invulnerable.of(dataset.sheetOf(unidad));
          if (inv != null && inv.isConditional) condicionadas++;
        }
      }
      expect(condicionadas, greaterThan(30),
          reason: 'Knights de los dos bandos, Rangers, Banshees y compañía');
    });
  });

  group('habilidades de reglamento', () {
    test('las líneas CORE y FACTION salen, que no salían en ninguna parte', () {
      // El dataset las enlaza con `infoLinks` de tipo `rule`, que no son perfiles. Wazdakka
      // Gutsmek salía sin Deep Strike, sin Lone Operative y sin Deadly Demise D3.
      final orks = dataset.factionNamed('Xenos - Orks');
      final wazdakka = orks.units.firstWhere((u) => u.name == 'Wazdakka Gutsmek');
      final suyas = dataset.abilitiesOf(wazdakka);

      expect(suyas.where((a) => a.isCore).map((a) => a.name),
          ['Deadly Demise D3', 'Deep Strike', 'Lone Operative']);
      expect(suyas.where((a) => a.isFaction).map((a) => a.name), ['Waaagh!']);
      // La X de «Deadly Demise X» la pone el enlace, no la regla: la regla es una para todos.
      expect(suyas.firstWhere((a) => a.name.startsWith('Deadly')).description,
          isNotEmpty);
    });

    test('y las tiene casi todo el dataset, no solo la unidad que se probó', () {
      var con = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          if (dataset.abilitiesOf(unidad).isNotEmpty) con++;
        }
      }
      expect(con, greaterThan(1200));
    });

    test('una palabra clave de arma se resuelve a su regla, con número o sin él', () {
      expect(dataset.ruleNamed('[SUSTAINED HITS 1]')?.name, 'Sustained Hits');
      expect(dataset.ruleNamed('LETHAL HITS: non-MONSTER/VEHICLE')?.name, 'Lethal Hits');
      expect(dataset.ruleNamed('ANTI-INFANTRY 4+')?.name, 'Anti');
      expect(dataset.ruleNamed('CLEAVE 2')?.name, 'Cleave');
      expect(dataset.ruleNamed('una cosa que no existe'), isNull);
    });
  });

  group('cuántas miniaturas llevan cada arma', () {
    test('la cuenta es la de quien la lleva, no la de veces que está puesta', () {
      final custodes = listaDe('Imperium - Adeptus Custodes');
      expect(dataset.weaponCountsOf(unidadDe(custodes, 'Custodian Guard'))['Guardian Spear'],
          4);

      final dg = listaDe('Chaos - Death Guard');
      final marines = unidadDe(dg, 'Plague Marines');
      // Cinco: cuatro rasos y el Campeón, cada uno con el suyo.
      expect(dataset.weaponCountsOf(marines)['Boltgun'], 5);
      expect(dataset.weaponCountsOf(unidadDe(dg, 'Poxwalkers'))['Improvised weapons'], 10);
    });
  });

  group('el tamaño de la escuadra', () {
    test('crece con el soldado raso, no con el sargento ni el arma especial', () {
      final roster = listaDe('Imperium - Adeptus Astartes - Ultramarines');
      final termis = unidadDe(roster, 'Terminator Squad');
      final grupo = termis.groups.firstWhere((g) => g.name == 'Terminators');

      expect(roster.groupUsage(termis, grupo).puestas, 5);
      expect(roster.defaultOptionFor(termis, grupo)?.name, 'Terminator w/ Power Fist',
          reason: 'el sargento ya está puesto y lleva tope de uno');
    });

    test('y el precio sube con ella: el dataset lo cuenta por grupo, no por entrada', () {
      // «Si hay 6 o más selecciones del grupo Terminators, esta unidad cuesta 320 en vez de 160».
      // El `childId` de una condición puede nombrar una entrada, una categoría **o un grupo**, y
      // lo tercero no se reconocía: una escuadra de diez se cobraba como una de cinco.
      final roster = listaDe('Imperium - Adeptus Astartes - Ultramarines');
      final termis = unidadDe(roster, 'Terminator Squad');
      roster.add(termis);
      expect(roster.points, 160);

      final grupo = termis.groups.firstWhere((g) => g.name == 'Terminators');
      while (roster.groupUsage(termis, grupo).puestas < 10) {
        final raso = roster.defaultOptionFor(termis, grupo)!;
        final puesta = termis.puestaDe(raso);
        if (puesta != null) {
          puesta.count++;
        } else {
          termis.addChild(raso);
        }
      }
      expect(roster.points, 320);
      expect(roster.validate().where((v) => v.selection != null), isEmpty);
    });

    test('lo mismo en otra facción, y con una escuadra sin tope declarado', () {
      final roster = listaDe('Chaos - Death Guard');
      final pox = unidadDe(roster, 'Poxwalkers');
      roster.add(pox);
      expect(roster.points, 65);

      final grupo = pox.groups.firstWhere((g) => g.name!.contains('Poxwalkers'));
      var vueltas = 0;
      while (vueltas++ < 40) {
        final raso = roster.defaultOptionFor(pox, grupo);
        if (raso == null || !roster.canAdd(pox, raso)) break;
        final puesta = pox.puestaDe(raso);
        if (puesta != null) {
          puesta.count++;
        } else {
          pox.addChild(raso);
        }
      }
      expect(roster.groupUsage(pox, grupo).puestas, 20, reason: 'el techo lo pone la opción');
      expect(roster.points, 130);
    });
  });

  group('cambiar el arma de una miniatura', () {
    test('no hace crecer la escuadra: se la quita a una de las que ya hay', () {
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      roster.add(marines);
      final escuadra =
          marines.groups.firstWhere((g) => roster.isModelGroup(marines, g));

      // Llena, que es donde antes se atascaba del todo.
      while (true) {
        final relleno = roster.defaultOptionFor(marines, escuadra);
        final uso = roster.groupUsage(marines, escuadra);
        if (relleno == null ||
            (uso.maximo != null && uso.puestas >= uso.maximo!) ||
            !roster.canAdd(marines, relleno)) {
          break;
        }
        final puesta = marines.puestaDe(relleno);
        if (puesta != null) {
          puesta.count++;
        } else {
          marines.addChild(relleno);
        }
      }
      expect(roster.groupUsage(marines, escuadra).puestas, 9);
      final puntos = roster.points;

      final plasma = roster
          .optionsFor(marines)
          .firstWhere((o) => o.name == 'Plague Marine w/ plasma gun');
      expect(roster.canAssign(marines, plasma), isTrue,
          reason: 'con la escuadra llena se le sigue pudiendo cambiar el arma a una');

      roster.assign(marines, plasma);
      expect(marines.cuantasDe(plasma), 1);
      expect(roster.groupUsage(marines, escuadra).puestas, 9,
          reason: 'sigue siendo de nueve: no se ha añadido una miniatura');
      expect(roster.points, puntos, reason: 'y cuesta lo mismo');
      expect(roster.validate().where((v) => v.selection != null), isEmpty);

      roster.unassign(marines, plasma);
      expect(marines.cuantasDe(plasma), 0);
      expect(roster.groupUsage(marines, escuadra).puestas, 9);
    });

    test('respeta el techo del arma y el de su subgrupo', () {
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      roster.add(marines);
      final especiales =
          marines.groups.firstWhere((g) => g.name == 'Special weapons');
      final tope = roster.groupUsage(marines, especiales).maximo;
      expect(tope, isNotNull);

      final plasma = roster
          .optionsFor(marines)
          .firstWhere((o) => o.name == 'Plague Marine w/ plasma gun');
      var puestas = 0;
      while (roster.canAssign(marines, plasma) && puestas < 20) {
        roster.assign(marines, plasma);
        puestas++;
      }
      expect(roster.groupUsage(marines, especiales).puestas, lessThanOrEqualTo(tope!));
      expect(roster.validate().where((v) => v.selection != null), isEmpty);
    });

    test('y deja de atascarse en casi todo el dataset, no solo aquí', () {
      // Con la escuadra llena, el arma y la miniatura competían por el mismo hueco: en 896 de las
      // 930 unidades con cambios de arma no se podía asignar ninguno. Las que quedan son las que
      // ya tienen todas sus armas al tope, que es otra cosa.
      var conCambios = 0;
      var atascadas = 0;
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 5000)
          ..battleSize = dataset.battleSizes.firstWhere((b) => b.pointsLimit == 2000);
        final suyos = dataset.detachmentsOf(faccion);
        if (suyos.isNotEmpty) roster.detachments.add(suyos.first);
        for (final entrada in faccion.units) {
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.units
            ..clear()
            ..add(unidad);
          final escuadras =
              unidad.groups.where((g) => roster.isModelGroup(unidad, g)).toList();
          if (escuadras.isEmpty) continue;
          for (final g in escuadras) {
            var vueltas = 0;
            while (vueltas++ < 40) {
              final relleno = roster.defaultOptionFor(unidad, g);
              final uso = roster.groupUsage(unidad, g);
              if (relleno == null ||
                  (uso.maximo != null && uso.puestas >= uso.maximo!) ||
                  !roster.canAdd(unidad, relleno)) {
                break;
              }
              final puesta = unidad.puestaDe(relleno);
              if (puesta != null) {
                puesta.count++;
              } else {
                unidad.addChild(relleno);
              }
            }
          }
          final cambios = roster
              .optionsFor(unidad)
              .where((o) => o.type == 'model' && !roster.isFiller(unidad, o))
              .where((o) => escuadras.any((g) => roster.modelGroupOf(unidad, o)?.id == g.id))
              .toList();
          if (cambios.isEmpty) continue;
          conCambios++;
          // Atascada de verdad: ni se puede asignar ni está todo al tope. «Al tope» es el suyo
          // propio —«hasta 2 lanzaplagas»— o el del subgrupo que las comparte, que es donde el
          // dataset escribe «hasta 3 armas especiales en toda la escuadra».
          final sinSitio = cambios.every((o) {
            final tope = roster.effectiveMaxOf(unidad, o);
            if (tope != null && unidad.cuantasDe(o) >= tope) return true;
            final suyo = unidad.groups.where((g) => g.id == o.groupId).firstOrNull;
            if (suyo == null) return false;
            final uso = roster.groupUsage(unidad, suyo);
            return uso.maximo != null && uso.puestas >= uso.maximo!;
          });
          if (!cambios.any((o) => roster.canAssign(unidad, o)) && !sinSitio) atascadas++;
        }
      }
      expect(conCambios, greaterThan(800));
      expect(atascadas, 0,
          reason: 'lo único que impide cambiar un arma es su propio techo');
    });
  });

  group('ruido del dataset', () {
    test('«Precise» no es una habilidad de la unidad y se va de todas', () {
      // Su texto es «cada vez que se consigue una herida crítica **con esta arma**…», que es la
      // explicación de [PRECISION]: habla de un arma, no de la unidad. Estaba en 594 unidades,
      // muchas de ellas vehículos y titánicas.
      var cuantas = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          if (dataset.sheetOf(unidad).any((p) => p.name == 'Precise')) cuantas++;
        }
      }
      expect(cuantas, 0);
    });

    test('pero las habilidades de verdad siguen ahí', () {
      final dg = dataset.factionNamed('Chaos - Death Guard');
      final blightlord = dg.units.firstWhere((u) => u.name == 'Blightlord Terminators');
      expect(dataset.sheetOf(blightlord).map((p) => p.name),
          contains('Blistering Fusillade'));
    });
  });

  group('líderes', () {
    test('la hoja que trae su excepción escrita se une aunque ya haya otro', () {
      // «Puedes adjuntar esta miniatura a una de las unidades anteriores aunque ya se le haya
      // adjuntado una miniatura Captain o Chapter Master.» Lo dicen ocho hojas del dataset.
      final blood = dataset.factionNamed('Imperium - Adeptus Astartes - Blood Angels');
      final sacerdote =
          blood.units.firstWhere((u) => u.name == 'Sanguinary Priest');
      expect(dataset.aceptaOtroLider(sacerdote), isTrue);

      final marines = blood.units.firstWhere((u) => u.name == 'Plague Marines',
          orElse: () => blood.units.firstWhere((u) => u.name == 'Intercessor Squad'));
      expect(dataset.aceptaOtroLider(marines), isFalse);
    });

    test('una anfitriona que ya lleve líder se ofrece igual, avisando', () {
      // Hay más excepciones en el juego que en el dataset: el Biologus Putrifier puede ser el
      // segundo y BSData no lo dice ni en inglés ni traducido. Esconder la unión dejaría al
      // jugador sin poder montar su lista y sin saber por qué.
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      final biologus = unidadDe(roster, 'Biologus Putrifier');
      final tallyman = unidadDe(roster, 'Tallyman');
      roster..add(marines)..add(biologus)..add(tallyman);

      expect(roster.hostsFor(tallyman), contains(marines));
      roster.attach(tallyman, marines);

      expect(roster.hostsFor(biologus), contains(marines),
          reason: 'se sigue ofreciendo aunque ya lleve uno');
      expect(roster.hostAlreadyLed(biologus, marines), isTrue,
          reason: 'y se avisa de que ya lleva uno');
    });

    test('y son pocas, así que la regla general sigue siendo una y una', () {
      var conExcepcion = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          if (dataset.aceptaOtroLider(unidad)) conExcepcion++;
        }
      }
      expect(conExcepcion, inInclusiveRange(5, 40));
    });
  });
}
