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

  setUpAll(() async => dataset = await Dataset.load(_datasetDirectory(), notas: File('../data/wargear/notas-de-equipo.json')));

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
      //
      // Se cuenta lo que **solo** existe en una mejora, no lo que comparte nombre con una: hay
      // habilidades de unidad que se llaman igual que una mejora —«Storm of Whispers» de Yvraine—
      // y armas también —el TL-409 de Adeptus Mechanicus—. Contando por nombre salían 883
      // «coladas» que eran contenido legítimo de la hoja.
      final soloDeMejoras = <String>{};
      for (final id in dataset.enhancementIds) {
        final entrada = dataset.node(id);
        if (entrada == null) continue;
        for (final p in dataset.profilesOf(entrada)) {
          soloDeMejoras.add('${p.typeName}|${p.name}');
        }
      }
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          final entrada = dataset.node(unidad.id);
          if (entrada == null) continue;
          for (final p in dataset.profilesOf(entrada)) {
            soloDeMejoras.remove('${p.typeName}|${p.name}');
          }
        }
      }

      var coladas = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          coladas += dataset
              .sheetOf(unidad)
              .where((p) => soloDeMejoras.contains('${p.typeName}|${p.name}'))
              .length;
        }
      }
      expect(coladas, lessThan(5), reason: 'antes eran 7.565');
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
          // Atascada de verdad: ni se puede asignar, ni está todo al tope, ni la escuadra está
          // en su suelo. «Al tope» es el suyo propio —«hasta 2 lanzaplagas»— o el del subgrupo que
          // las comparte, que es donde el dataset escribe «hasta 3 armas especiales en toda la
          // escuadra»; y «en su suelo» es que no quede a quién quitarle el arma sin bajar de un
          // mínimo, como el Spectrus Kill Team con sus cinco Infiltrators.
          final enElSuelo = escuadras.every((g) {
            final relleno = roster.defaultOptionFor(unidad, g);
            return relleno == null || !roster.canRemove(unidad, relleno);
          });
          final sinSitio = enElSuelo ||
              cambios.every((o) {
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

  group('una miniatura que a su vez pregunta', () {
    test('entra con su elección puesta, no con el hueco abierto', () {
      // El «Terminator w/ Heavy Weapon» no dice cuál: pregunta entre assault cannon, heavy flamer
      // y cyclone. Entraba con ese hueco vacío, la unidad quedaba ilegal y no había pantalla desde
      // la que rellenarlo.
      final roster = listaDe('Imperium - Adeptus Astartes - Ultramarines');
      final termis = unidadDe(roster, 'Terminator Squad');
      roster.add(termis);

      final pesado = roster
          .optionsFor(termis)
          .firstWhere((o) => o.name == 'Terminator w/ Heavy Weapon');
      expect(roster.canAssign(termis, pesado), isTrue);
      roster.assign(termis, pesado);

      final puesto = termis.puestaDe(pesado)!;
      expect(puesto.groups.map((g) => g.name), contains('Ranged Weapon Option'));
      expect(puesto.children, isNotEmpty,
          reason: 'entra con un arma puesta, que se cambia de un toque');
      expect(roster.validate().where((v) => v.selection != null), isEmpty,
          reason: 'y sin dejar la unidad ilegal');

      // Y la elección sigue estando: es un grupo con sus opciones, no una fila muerta.
      expect(roster.optionsFor(puesto).map((o) => o.name),
          containsAll(['Heavy Flamer', 'Assault Cannon']));
    });

    test('y una escuadra con suelo propio no se le baja para hacer sitio', () {
      // El Spectrus Kill Team exige cinco Infiltrators. Cambiarle el arma a uno los dejaba en
      // cuatro y la unidad ilegal: ahí primero se crece la escuadra y luego se cambia.
      final sororitas = listaDe('Imperium - Adepta Sororitas');
      final entrada = sororitas.faction.units
          .firstWhere((u) => u.name == 'Spectrus Kill Team [Legends]');
      final equipo = sororitas.selectionFor(entrada);
      sororitas.add(equipo);

      final conMochila = sororitas
          .optionsFor(equipo)
          .firstWhere((o) => o.name == 'Kill Team Infiltrator w/ jump pack');
      expect(sororitas.canAssign(equipo, conMochila), isFalse,
          reason: 'la escuadra está justo en su mínimo');
      expect(sororitas.validate().where((v) => v.selection != null), isEmpty);
    });

    test('y lo que ocupa dos huecos se lleva dos, que es lo que dice el dataset', () {
      // El Heavy Weapons Team son dos soldados: al ponerlo, el techo de la escuadra baja de nueve
      // a ocho. Quitando solo uno la unidad quedaba pasada de su propio máximo.
      final guardia = listaDe('Imperium - Astra Militarum');
      final entrada = guardia.faction.units
          .firstWhere((u) => u.name == 'Death Korps Grenadier Squad [Legends]');
      final escuadra = guardia.selectionFor(entrada);
      guardia.add(escuadra);
      expect(guardia.validate().where((v) => v.selection != null), isEmpty);

      final pesado = guardia
          .optionsFor(escuadra)
          .firstWhere((o) => o.name == 'Heavy Weapons Team');
      guardia.assign(escuadra, pesado);

      expect(escuadra.cuantasDe(pesado), 1);
      expect(guardia.validate().where((v) => v.selection != null), isEmpty,
          reason: 'la escuadra vuelve a caber en su techo');
    });

    test('y ninguna unidad del dataset queda con un hueco así al cambiarle un arma', () {
      var probadas = 0;
      var ilegales = 0;
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
          if (roster.validate().where((v) => v.selection != null).isNotEmpty) continue;
          final cambios = roster
              .optionsFor(unidad)
              .where((o) => o.type == 'model' && roster.canAssign(unidad, o))
              .toList();
          if (cambios.isEmpty) continue;
          probadas++;
          roster.assign(unidad, cambios.first);
          if (roster.validate().where((v) => v.selection != null).isNotEmpty) ilegales++;
        }
      }
      expect(probadas, greaterThan(500));
      expect(ilegales, 0, reason: 'cambiar un arma nunca deja un hueco sin rellenar');
    });
  });

  group('la hoja del catálogo', () {
    test('trae todas las armas que la unidad puede llevar', () {
      // El dataset mete las armas en subgrupos —«Wargear» contiene «Ranged Weapon Option»— y
      // mirando solo los grupos de primer nivel no se llegaba a ninguna: eran 4.484 perfiles sin
      // enseñar en 686 de las 1.485 unidades. El Autarch salía sin una sola arma.
      final aeldari = dataset.factionNamed('Xenos - Aeldari');
      final autarch = aeldari.units.firstWhere((u) => u.name == 'Autarch');
      final hoja = dataset.sheetOf(autarch);

      expect(hoja.where((p) => p.typeName.contains('Weapons')), isNotEmpty);
      expect(hoja.map((p) => p.name),
          containsAll(['Scorpion Chainsword', 'Banshee Blade', 'Star Glaive']));
    });

    test('y ninguna unidad del dataset se queda sin las suyas', () {
      var sinArmas = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        final roster = Roster(faction: faccion, pointsLimit: 3000);
        final suyos = dataset.detachmentsOf(faccion);
        if (suyos.isNotEmpty) roster.detachments.add(suyos.first);
        for (final entrada in faccion.units) {
          if (!vistas.add(entrada.id)) continue;
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          // Si el árbol de la unidad ofrece un arma, la hoja tiene que enseñarla.
          final enLaHoja = dataset
              .sheetOf(entrada)
              .where((p) => p.typeName.contains('Weapons'))
              .map((p) => p.name)
              .toSet();
          final ofrecidas = <String>{};
          for (final nodo in unidad.descendantsAndSelf) {
            for (final opcion in roster.optionsFor(nodo)) {
              final entry = dataset.node(opcion.entryId);
              if (entry == null) continue;
              for (final p in dataset.profilesOf(entry)) {
                if (p.typeName.contains('Weapons')) ofrecidas.add(p.name);
              }
            }
          }
          if (ofrecidas.difference(enLaHoja).isNotEmpty) sinArmas++;
        }
      }
      expect(sinArmas, 0);
    });
  });

  group('las opciones de equipo de la hoja', () {
    test('salen con las palabras de la hoja, que es lo que BSData no trae', () {
      final ultra = dataset.factionNamed('Imperium - Adeptus Astartes - Ultramarines');
      final termis = ultra.units.firstWhere((u) => u.name == 'Terminator Squad');
      final notas = dataset.wargearNotesOf(termis);

      expect(notas, isNotEmpty);
      expect(notas.first, contains('For every 5 models in this unit'));
      expect(notas.first, contains('storm bolter can be replaced'));
      expect(notas.join(' '), contains('assault cannon'));
    });

    test('y en otra facción igual, con las suyas', () {
      final dg = dataset.factionNamed('Chaos - Death Guard');
      final marines = dg.units.firstWhere((u) => u.name == 'Plague Marines');
      final notas = dataset.wargearNotesOf(marines);

      expect(notas, hasLength(7));
      expect(notas.join(' '), contains('For every 5 models in this unit'));
      expect(notas.join(' '), contains('blight launcher'));

      final custodes = dataset.factionNamed('Imperium - Adeptus Custodes');
      final guardia = custodes.units.firstWhere((u) => u.name == 'Custodian Guard');
      expect(dataset.wargearNotesOf(guardia).join(' '), contains('guardian spear'));
    });

    test('pero la frase que ya no vale no se enseña', () {
      // El texto es de las index cards de 10ª. El Defiler de entonces llevaba un twin heavy
      // flamer y un reaper autocannon; el de ahora, un baleflamer y un cañón Hades. Enseñar esa
      // frase sería peor que no enseñar ninguna.
      final dg = dataset.factionNamed('Chaos - Death Guard');
      final defiler = dg.units.firstWhere((u) => u.name == 'Defiler');
      expect(dataset.wargearNotesOf(defiler), isEmpty);
    });

    test('llegan a cientos de unidades, no a un puñado', () {
      var con = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          if (dataset.wargearNotesOf(unidad).isNotEmpty) con++;
        }
      }
      expect(con, greaterThan(400));
    });

    test('y no deciden nada: sin ellas la lista sale igual', () {
      // Es texto de otra edición, así que no puede tocar ni los topes ni el precio. Lo único que
      // cambia al quitarlas es que no hay frase que leer.
      final dg = dataset.factionNamed('Chaos - Death Guard');
      final entrada = dg.units.firstWhere((u) => u.name == 'Plague Marines');

      final conNotas = Roster(faction: dg, pointsLimit: 2000)
        ..detachments.add(dataset.detachmentsOf(dg).first);
      conNotas.add(conNotas.selectionFor(entrada));
      final puntos = conNotas.points;
      final avisos = conNotas.validate().length;

      final guardadas = dataset.notasDeEquipo;
      dataset.notasDeEquipo = const NotasDeEquipo.vacia();
      try {
        final sinNotas = Roster(faction: dg, pointsLimit: 2000)
          ..detachments.add(dataset.detachmentsOf(dg).first);
        sinNotas.add(sinNotas.selectionFor(entrada));
        expect(sinNotas.points, puntos);
        expect(sinNotas.validate(), hasLength(avisos));
        expect(dataset.wargearNotesOf(entrada), isEmpty);
      } finally {
        dataset.notasDeEquipo = guardadas;
      }
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
    test('la excepción del Biologus la escribe la propia escuadra, no una lista a mano', () {
      // Plague Marines declara «máximo 1 Leader» y un modifier que lo sube a 2 si uno de los
      // unidos es un Biologus Putrifier, un Tallyman, un Foul Blightspawn… Se evalúa tal cual.
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      final biologus = unidadDe(roster, 'Biologus Putrifier');
      final tallyman = unidadDe(roster, 'Tallyman');
      final otroTallyman = unidadDe(roster, 'Tallyman');
      roster..add(marines)..add(biologus)..add(tallyman)..add(otroTallyman);

      expect(roster.attach(tallyman, marines), isNull);
      expect(roster.motivoParaUnir(biologus, marines), isNull);
      expect(roster.attach(biologus, marines), isNull);
      expect(roster.leadersOn(marines).length, 2);

      // Un tercero se sigue ofreciendo, pero deshabilitado y con el motivo.
      expect(roster.hostsFor(otroTallyman), contains(marines));
      expect(roster.motivoParaUnir(otroTallyman, marines),
          'Plague Marines ya lleva 2 de 2 Leader');
      expect(roster.attach(otroTallyman, marines), isNotNull);
      expect(otroTallyman.attachedTo, isNull);
    });

    test('a quién se une cada personaje sale de sus asociaciones en todo el dataset', () {
      var lideres = 0;
      final vistas = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistas.add(unidad.id)) continue;
          if (dataset.isLeader(unidad)) lideres++;
        }
      }
      expect(lideres, greaterThan(400));
    });
  });

  group('cuántas miniaturas dice que hay', () {
    /// Crece la escuadra hasta donde deje.
    int alMaximo(Roster r, Selection u, OptionGroup esc) {
      for (var i = 0; i < 40; i++) {
        final uso = r.groupUsage(u, esc);
        if (uso.maximo != null && uso.puestas >= uso.maximo!) break;
        final o = r.defaultOptionFor(u, esc);
        if (o == null || !r.canAdd(u, o)) break;
        final puesta = u.puestaDe(o);
        if (puesta != null) {
          puesta.count++;
        } else {
          u.addChild(o);
          r.completeMinimums(o);
        }
        r.applyModifiers();
      }
      return r.squadTally(u, esc).puestas;
    }

    test('el sargento también cuenta, esté suelto o en un grupo suyo', () {
      // Una escuadra de diez Plague Marines se leía «9»: el dataset saca al Plague Champion del
      // grupo y la barra enseñaba las puestas del grupo a secas. Y hay dos formas de sacarlo —hijo
      // suelto, o grupo propio de uno—, así que hacían falta las dos.
      for (final caso in [
        ('Chaos - Death Guard', 'Plague Marines', 10),
        ('Chaos - Death Guard', 'Blightlord Terminators', 10),
        ('Chaos - Chaos Space Marines', 'Chaos Terminator Squad', 10),
        ('Chaos - Chaos Space Marines', 'Chosen', 10),
      ]) {
        final roster = listaDe(caso.$1);
        final unidad = unidadDe(roster, caso.$2);
        roster.add(unidad);
        roster.applyModifiers();
        final escuadra = roster.mainModelGroup(unidad)!;
        expect(alMaximo(roster, unidad, escuadra), caso.$3, reason: caso.$2);
      }
    });

    test('y en todo el dataset la barra dice las miniaturas que hay', () {
      var conEscuadra = 0, cuadran = 0;
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          final principal = roster.mainModelGroup(unidad);
          if (principal == null) continue;
          conEscuadra++;
          final miniaturas = unidad.children
              .where((c) => c.type == 'model')
              .fold<int>(0, (t, c) => t + c.count);
          if (roster.squadTally(unidad, principal).puestas == miniaturas) cuadran++;
        }
      }
      expect(conEscuadra, greaterThan(1000));
      // Las que faltan son unidades con dos escuadras que se dimensionan por separado —los
      // Inquisitorial Agents son Acolytes y Gun Servitors—, y ahí dos barras es lo correcto.
      expect(cuadran, greaterThan(conEscuadra - 30),
          reason: 'la barra de la escuadra dice las miniaturas que hay');
    });

    test('el «−» nunca deja la unidad ilegal', () {
      // El dataset escribe algunos mínimos en la propia miniatura —«Spindle Drone: mínimo 4»— y el
      // grupo no dice nada. Mirando solo el grupo, el botón se dejaba pulsar y la unidad quedaba
      // ilegal: pasaba en 134 grupos.
      var mirados = 0, rompen = 0;
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          if (roster.validate().isNotEmpty) continue;
          for (final grupo in unidad.groups.where((g) => roster.isModelGroup(unidad, g))) {
            final victima = roster.shrinkTarget(unidad, grupo);
            if (victima == null) continue;
            mirados++;
            final puesta = unidad.puestaDe(victima);
            if (puesta == null) continue;
            if (puesta.count > 1) {
              puesta.count--;
            } else {
              unidad.children.remove(puesta);
            }
            roster.applyModifiers();
            final mal = roster
                .validate()
                .where((v) => v.selection == unidad || v.selection?.parent == unidad);
            if (mal.isNotEmpty) rompen++;
            final otra = unidad.puestaDe(victima);
            if (otra != null) {
              otra.count++;
            } else {
              unidad.addChild(victima);
            }
            roster.applyModifiers();
          }
        }
      }
      expect(rompen, 0, reason: 'de $mirados quitadas que la app ofrece');
    });

    test('pero se sigue pudiendo encoger una escuadra que ha crecido', () {
      // El arreglo anterior es un candado, y un candado de más es el otro fallo: hay que poder
      // deshacer lo que se acaba de añadir.
      final roster = listaDe('Chaos - Death Guard');
      final unidad = unidadDe(roster, 'Plague Marines');
      roster.add(unidad);
      roster.applyModifiers();
      final escuadra = roster.mainModelGroup(unidad)!;
      final antes = roster.squadTally(unidad, escuadra).puestas;
      alMaximo(roster, unidad, escuadra);
      expect(roster.squadTally(unidad, escuadra).puestas, greaterThan(antes));
      expect(roster.shrinkTarget(unidad, escuadra), isNotNull,
          reason: 'lo que se ha añadido se puede quitar');
    });
  });

  group('los topes que el dataset no escribe contra el padre', () {
    test('«dos en esta unidad» también es un tope', () {
      // El «Rough Rider w/ Goad lance» lleva su techo contra el id de la propia unidad, no contra
      // `parent`. Mirando solo `parent` y `self` no había techo ninguno y la app dejaba poner una
      // lanza en cada miniatura, donde la hoja pone «una por cada cinco».
      final roster = listaDe('Imperium - Astra Militarum');
      final unidad = unidadDe(roster, 'Attilan Rough Riders');
      roster.add(unidad);
      roster.applyModifiers();
      final lanza = roster
          .optionsFor(unidad)
          .firstWhere((o) => o.name.toLowerCase().contains('goad'));
      // Uno con cinco jinetes, que es lo que dice la hoja —«una por cada cinco»—, y dos al
      // llenar la escuadra. El techo del dataset, 2, es el de la escuadra llena.
      expect(roster.effectiveMaxOf(unidad, lanza), 1);

      final escuadra = roster.mainModelGroup(unidad)!;
      for (var i = 0; i < 20; i++) {
        final uso = roster.groupUsage(unidad, escuadra);
        if (uso.maximo != null && uso.puestas >= uso.maximo!) break;
        final relleno = roster.defaultOptionFor(unidad, escuadra);
        if (relleno == null || !roster.canAdd(unidad, relleno)) break;
        final puesta = unidad.puestaDe(relleno);
        if (puesta != null) {
          puesta.count++;
        } else {
          unidad.addChild(relleno);
        }
        roster.applyModifiers();
      }
      expect(roster.effectiveMaxOf(unidad, lanza), 2);
    });

    test('y con eso hay techo conocido en casi todas las opciones de arma', () {
      var opciones = 0, conTecho = 0;
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          for (final opcion in roster.optionsFor(unidad)) {
            if (roster.modelGroupOf(unidad, opcion) == null) continue;
            opciones++;
            if (roster.effectiveMaxOf(unidad, opcion) != null) conTecho++;
          }
        }
      }
      expect(opciones, greaterThan(3500));
      expect(conTecho, greaterThan(3840), reason: 'eran 3.818 de $opciones');
    });
  });

  group('una unidad recién metida no puede estar ya ilegal', () {
    test('el hueco obligatorio se rellena aunque el dataset señale a un id que no ofrece', () {
      // El Desolation Sergeant marca de serie un id que no es ninguna de sus dos opciones, y
      // dándolo por imposible la unidad entraba en la lista con «Weapon Option: mínimo 1, hay 0»
      // nada más añadirla, en catorce facciones.
      final roster = listaDe('Imperium - Adeptus Astartes - Space Marines');
      final unidad = unidadDe(roster, 'Desolation Squad');
      roster.add(unidad);
      roster.applyModifiers();
      expect(roster.validate().where((v) => v.selection?.parent == unidad), isEmpty);
    });

    test('y en todo el dataset son pocas y se sabe cuáles', () {
      final malas = <String>[];
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          // Sin contar el aviso de un apoyo que tiene que ir unido: con la unidad sola en la
          // lista todavía no hay a quién unirlo, y no es un fallo de cómo entra.
          final suyas = roster.validate().where((v) =>
              (v.selection == unidad || v.selection?.parent == unidad) &&
              !v.message.endsWith('tiene que ir unido a una unidad'));
          if (suyas.isNotEmpty) malas.add(entrada.name);
        }
      }
      // Las que quedan son sobre todo unidades [Crucible], donde el grupo obligatorio no ofrece
      // ninguna opción: ahí no hay nada que poner y no se va a inventar.
      expect(malas.length, lessThan(40), reason: 'eran 45: ${malas.toSet()}');
    });
  });

  group('por cada 5 miniaturas, 1 arma', () {
    test('con media escuadra caben la mitad de armas', () {
      // BSData deja el techo del blight launcher en 2 —el de una escuadra de diez— y mete el «uno
      // por cada cinco» en un modifier de tipo `error`, que solo pinta un aviso. Con cinco Plague
      // Marines la app dejaba poner dos blight launchers y dos plague spewers: cuatro armas
      // especiales en una escuadra de cinco.
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      roster.add(marines);
      roster.applyModifiers();

      Selection opcion(String nombre) =>
          roster.optionsFor(marines).firstWhere((o) => o.name.contains(nombre));

      expect(roster.effectiveMaxOf(marines, opcion('blight launcher')), 1);
      expect(roster.effectiveMaxOf(marines, opcion('plague spewer')), 1);
      expect(roster.effectiveMaxOf(marines, opcion('bubotic weapons')), 2);
      expect(roster.effectiveMaxOf(marines, opcion('heavy plague weapon')), 2);

      // Y al crecer a diez, el doble.
      final escuadra = roster.mainModelGroup(marines)!;
      for (var i = 0; i < 20; i++) {
        final uso = roster.groupUsage(marines, escuadra);
        if (uso.maximo != null && uso.puestas >= uso.maximo!) break;
        final relleno = roster.defaultOptionFor(marines, escuadra);
        if (relleno == null || !roster.canAdd(marines, relleno)) break;
        final puesta = marines.puestaDe(relleno);
        if (puesta != null) {
          puesta.count++;
        } else {
          marines.addChild(relleno);
        }
        roster.applyModifiers();
      }
      expect(roster.effectiveMaxOf(marines, opcion('blight launcher')), 2);
      expect(roster.effectiveMaxOf(marines, opcion('bubotic weapons')), 4);
    });

    test('«una de las siguientes» es una miniatura eligiendo, no una por arma', () {
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      roster.add(marines);
      roster.applyModifiers();
      Selection opcion(String nombre) =>
          roster.optionsFor(marines).firstWhere((o) => o.name.contains(nombre));

      roster.assign(marines, opcion('meltagun'));
      roster.applyModifiers();
      expect(roster.canAssign(marines, opcion('plasma gun')), isFalse);
      expect(roster.canAssign(marines, opcion('plague belcher')), isFalse);
      expect(roster.canAssign(marines, opcion('blight launcher')), isTrue,
          reason: 'esa es otra frase y tiene su propio hueco');
      expect(roster.validate(), isEmpty);
    });

    test('la frase se lee bien en las 36 facciones y nunca deja un arma en cero', () {
      var conReglas = 0, conTope = 0, aCero = 0;
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          if (roster.reglasDeTopeDe(unidad).isEmpty) continue;
          conReglas++;
          for (final opcion in roster.optionsFor(unidad)) {
            if (roster.modelGroupOf(unidad, opcion) == null) continue;
            final impreso = roster.topeImpresoDe(unidad, opcion);
            if (impreso == null) continue;
            conTope++;
            if (impreso < 1) aCero++;
          }
        }
      }
      expect(conReglas, greaterThan(150));
      expect(conTope, greaterThan(140));
      // Un cero escondería todas las opciones de la unidad por una cuenta que no es del jugador.
      expect(aCero, 0);
    });
  });

  group('dos armas iguales que preguntan son dos miniaturas', () {
    test('cada una elige la suya', () {
      // «2 × Terminator w/ Heavy Weapon» con un solo desplegable dentro obligaba a que las dos
      // llevaran lo mismo. La hoja dice lo contrario: una puede llevar cyclone y otra assault
      // cannon.
      final roster = listaDe('Imperium - Adeptus Astartes - Ultramarines');
      final escuadra = unidadDe(roster, 'Terminator Squad');
      roster.add(escuadra);
      roster.applyModifiers();
      final grupo = roster.mainModelGroup(escuadra)!;
      for (var i = 0; i < 20; i++) {
        final uso = roster.groupUsage(escuadra, grupo);
        if (uso.maximo != null && uso.puestas >= uso.maximo!) break;
        final relleno = roster.defaultOptionFor(escuadra, grupo);
        if (relleno == null || !roster.canAdd(escuadra, relleno)) break;
        final puesta = escuadra.puestaDe(relleno);
        if (puesta != null) {
          puesta.count++;
        } else {
          escuadra.addChild(relleno);
        }
        roster.applyModifiers();
      }

      Selection pesada() => roster
          .optionsFor(escuadra)
          .firstWhere((o) => o.name.contains('Heavy Weapon'));

      roster.assign(escuadra, pesada());
      roster.applyModifiers();
      roster.assign(escuadra, pesada());
      roster.applyModifiers();

      final instancias = roster.instanciasDe(escuadra, pesada());
      expect(instancias.length, 2, reason: 'dos miniaturas, no un contador con un «×2»');

      // Y a la segunda se le cambia el arma sin tocar la primera.
      final segunda = instancias[1];
      final otra = roster
          .optionsFor(segunda)
          .firstWhere((o) => segunda.children.every((c) => c.entryId != o.entryId));
      segunda.children.removeWhere((c) => c.groupId == otra.groupId);
      segunda.addChild(otra);
      roster.applyModifiers();

      expect(instancias[0].children.map((c) => c.name),
          isNot(equals(instancias[1].children.map((c) => c.name))));
      expect(roster.validate(), isEmpty);
    });
  });

  group('el Warlord', () {
    test('es uno y solo uno en todo el ejército', () {
      final roster = listaDe('Chaos - Death Guard');
      final typhus = unidadDe(roster, 'Typhus');
      final tallyman = unidadDe(roster, 'Tallyman');
      roster..add(typhus)..add(tallyman);

      roster.setWarlord(typhus);
      expect(roster.isWarlord(typhus), isTrue);

      roster.setWarlord(tallyman);
      expect(roster.isWarlord(tallyman), isTrue);
      expect(roster.isWarlord(typhus), isFalse);
      expect(roster.warlord, tallyman);
    });

    test('y en los Supreme Commander no se elige: lo son', () {
      // «Si esta miniatura está en tu ejército, debe ser tu WARLORD». Lo llevan nueve unidades del
      // dataset, y ofrecerlo como casilla es ofrecer una elección que la regla no da.
      final roster = listaDe('Imperium - Adeptus Astartes - Ultramarines');
      final guilliman = unidadDe(roster, 'Roboute Guilliman');
      final otro = roster.faction.units
          .where((u) => u.name == 'Terminator Squad')
          .map(roster.selectionFor)
          .first;
      roster..add(guilliman)..add(otro);

      expect(roster.mustBeWarlord(guilliman), isTrue);
      roster.ajustarWarlord();
      expect(roster.isWarlord(guilliman), isTrue);

      // Y no se le puede quitar.
      roster.clearWarlord(guilliman);
      expect(roster.isWarlord(guilliman), isTrue);
    });

    test('son nueve en todo el dataset, no una regla inventada', () {
      var supremos = 0;
      final vistos = <String>{};
      for (final faccion in dataset.factions) {
        for (final unidad in faccion.units) {
          if (!vistos.add(unidad.id)) continue;
          if (dataset.debeSerWarlord(unidad)) supremos++;
        }
      }
      expect(supremos, inInclusiveRange(5, 30));
    });
  });

  group('los puntos de una unidad, tras un cambio', () {
    test('crecer la escuadra suma lo que toca, no se queda clavado', () {
      // El motor de precios ya estaba bien —lo que fallaba era que la app no volvía a llamar a
      // `applyModifiers` tras cada cambio, así que el número se quedaba con el de antes hasta que
      // algo distinto forzaba el recálculo. Parecía que los puntos se doblaban; estaban congelados
      // y saltaban tarde, a un valor de otro momento.
      final roster = listaDe('Imperium - Adeptus Custodes');
      final guardia = unidadDe(roster, 'Custodian Guard');
      roster.add(guardia);
      roster.applyModifiers();
      expect(guardia.points, 170);

      final grupo = roster.mainModelGroup(guardia)!;
      final relleno = roster.defaultOptionFor(guardia, grupo)!;
      final puesta = guardia.puestaDe(relleno);
      if (puesta != null) {
        puesta.count++;
      } else {
        guardia.addChild(relleno);
      }
      roster.applyModifiers();
      expect(guardia.points, 215, reason: 'cinco Guardias Custodios, no el doble de cuatro');
    });

    test('un grupo de armas especiales vacío no es la escuadra principal', () {
      // Los Skitarii Rangers llevan su equipo de serie suelto, sin grupo: «Skitarii Ranger w/
      // galvanic rifle» no vive dentro de «Skitarii Rangers Options», que solo ofrece las
      // alternativas. Contando ese grupo vacío como la escuadra principal, el «+» no crecía nada
      // y el precio se quedaba clavado en 85 por más veces que se pulsara.
      final roster = listaDe('Imperium - Adeptus Mechanicus');
      final rangers = unidadDe(roster, 'Skitarii Rangers');
      roster.add(rangers);
      roster.applyModifiers();
      expect(roster.mainModelGroup(rangers), isNull,
          reason: 'diez Skitarii Rangers es un número fijo, no hay grupo que lo decida');
    });

    test('y en todo el dataset, crecer una escuadra nunca deja el precio igual o lo dobla', () {
      var conEscuadra = 0, sanos = 0;
      final rotos = <String>[];
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();
          final grupo = roster.mainModelGroup(unidad);
          if (grupo == null) continue;
          final uso = roster.groupUsage(unidad, grupo);
          if (uso.maximo != null && uso.puestas >= uso.maximo!) continue;
          final relleno = roster.defaultOptionFor(unidad, grupo);
          if (relleno == null || !roster.canAdd(unidad, relleno)) continue;
          conEscuadra++;

          final antes = unidad.points;
          final puesta = unidad.puestaDe(relleno);
          if (puesta != null) {
            puesta.count++;
          } else {
            unidad.addChild(relleno);
            roster.completeMinimums(relleno);
          }
          roster.applyModifiers();
          final despues = unidad.points;
          final sano = despues > antes && despues < antes * 3;
          if (sano) {
            sanos++;
          } else if (rotos.length < 15) {
            rotos.add('[${faccion.name}] ${entrada.name}: $antes -> $despues');
          }
        }
      }
      expect(conEscuadra, greaterThan(700));
      // Lo que queda son formaciones de precio plano de verdad —Inquisitorial Agents lleva un
      // `set` incondicional a 60— y una unidad que ya nace ilegal, documentada aparte.
      expect(sanos, greaterThan(conEscuadra - 35), reason: rotos.join('; '));
    });
  });

  group('«hay alternativas» solo cuando de verdad las hay', () {
    test('el Biologus Putrifier no puede bajar su equipo de serie a cero', () {
      // El Biologus lleva Hyper blight grenades, Injector pistol y Plague knives a la vez, los
      // tres en el mismo grupo «Wargear», y ese grupo no tiene techo: no compiten entre sí, las
      // lleva todas. Contando «hay más de una opción en el grupo» como alternativas, el «−» las
      // dejaba bajar a cero como si sobrase elegir.
      final roster = listaDe('Chaos - Death Guard');
      final biologus = unidadDe(roster, 'Biologus Putrifier');
      roster.add(biologus);
      roster.applyModifiers();
      for (final nombre in ['Hyper blight grenades', 'Injector pistol', 'Plague knives']) {
        final opcion =
            roster.optionsFor(biologus).firstWhere((o) => o.name == nombre);
        expect(roster.canRemove(biologus, opcion, hayAlternativas: false), isFalse,
            reason: '$nombre es equipo de serie');
      }
    });

    test('y en todo el dataset, un grupo sin techo con varias puestas nunca deja vaciarlas', () {
      var grupos = 0, sanos = 0;
      for (final faccion in dataset.factions) {
        for (final entrada in faccion.units) {
          final roster = listaDe(faccion.name);
          Selection unidad;
          try {
            unidad = roster.selectionFor(entrada);
          } catch (_) {
            continue;
          }
          roster.add(unidad);
          roster.applyModifiers();

          void mirar(Selection nodo, int profundidad) {
            if (profundidad > 4) return;
            for (final grupo in nodo.groups) {
              if (roster.isModelGroup(nodo, grupo)) continue;
              final mias =
                  roster.optionsFor(nodo).where((o) => o.groupId == grupo.id).toList();
              if (mias.length < 2) continue;
              final uso = roster.groupUsage(nodo, grupo);
              if (uso.maximo != null) continue;
              final puestas = nodo.children.where((c) => c.groupId == grupo.id).toList();
              if (puestas.length < 2) continue;
              grupos++;
              final todasFijas = puestas.every(
                  (p) => !roster.canRemove(nodo, p, hayAlternativas: false));
              if (todasFijas) sanos++;
            }
            for (final hijo in nodo.children) {
              mirar(hijo, profundidad + 1);
            }
          }

          mirar(unidad, 0);
        }
      }
      expect(grupos, greaterThan(2000));
      expect(sanos, grupos);
    });
  });

  group('nunca más de dos líderes sobre la misma unidad', () {
    test('el tercero ya no se ofrece', () {
      // Cuatro Tallyman distintos, intentando unirse todos a la misma escuadra. Plague Marines
      // admite dos Leader si uno es un Tallyman —su modifier lo dice—, y ni uno más.
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      roster.add(marines);
      final instancias = <Selection>[
        for (var i = 0; i < 4; i++) unidadDe(roster, 'Tallyman'),
      ];
      for (final l in instancias) {
        roster.add(l);
      }
      var unidos = 0;
      for (final l in instancias) {
        if (roster.hostsFor(l).contains(marines) && roster.attach(l, marines) == null) {
          unidos++;
        }
      }
      expect(unidos, 2);
      expect(roster.leadersOn(marines).length, 2);
    });

    test('dos excepciones que se aceptan entre sí no se encadenan sin límite', () {
      // El Chaplain Grimaldus no acepta otro; el Castellan y el Crusade Ancient sí, cada uno con
      // su propia excepción escrita. Antes eso los dejaba apilar sin freno: cada uno se
      // justificaba solo con la suya, sin mirar cuántos había ya, y una Crusader Squad terminaba
      // con cuatro líderes encima.
      final roster = listaDe('Imperium - Adeptus Astartes - Black Templars');
      final crusader = unidadDe(roster, 'Crusader Squad');
      roster.add(crusader);
      final nombres = ['Chaplain Grimaldus', 'Castellan', 'Crusade Ancient', 'Apothecary'];
      var unidos = 0;
      for (final nombre in nombres) {
        final entrada =
            roster.faction.units.where((u) => u.name == nombre).firstOrNull;
        if (entrada == null) continue;
        final l = roster.selectionFor(entrada);
        roster.add(l);
        if (roster.hostsFor(l).contains(crusader) && roster.attach(l, crusader) == null) {
          unidos++;
        }
      }
      expect(roster.leadersOn(crusader).length, lessThanOrEqualTo(2));
      expect(unidos, lessThanOrEqualTo(2));
    });

    test('el Biologus Putrifier sigue pudiendo ser el segundo', () {
      // Lo dice un modifier de Plague Marines sobre su límite de Leader.
      final roster = listaDe('Chaos - Death Guard');
      final marines = unidadDe(roster, 'Plague Marines');
      final tallyman = unidadDe(roster, 'Tallyman');
      final biologus = unidadDe(roster, 'Biologus Putrifier');
      roster..add(marines)..add(tallyman)..add(biologus);
      roster.attach(tallyman, marines);
      expect(roster.hostsFor(biologus), contains(marines));
      expect(roster.attach(biologus, marines), isNull);
      expect(roster.leadersOn(marines).length, 2);
    });

    test('y en todo el dataset, ningún anfitrión termina con más de dos Leader', () {
      var facciones = 0, rotos = 0;
      for (final faccion in dataset.factions) {
        final roster = listaDe(faccion.name);
        final lideres = faccion.units.where(dataset.isLeader).take(15).toList();
        if (lideres.isEmpty) continue;
        facciones++;
        final anfitriones = <Selection>[];
        for (final u in faccion.units.take(30)) {
          Selection s;
          try {
            s = roster.selectionFor(u);
          } catch (_) {
            continue;
          }
          roster.add(s);
          anfitriones.add(s);
        }
        for (final l in lideres) {
          Selection sl;
          try {
            sl = roster.selectionFor(l);
          } catch (_) {
            continue;
          }
          roster.add(sl);
          final ofrecidos = roster.hostsFor(sl);
          if (ofrecidos.isNotEmpty) roster.attach(sl, ofrecidos.first);
        }
        for (final host in anfitriones) {
          final lideres = roster.leadersOn(host)
              .where((l) => roster.categoriesOf(l).contains('1556-9b56-fba6-4370'));
          if (lideres.length > 2) rotos++;
        }
      }
      expect(facciones, greaterThan(20));
      expect(rotos, 0);
    });
  });

  group('la disposición de fuerza de cada detachment', () {
    test('sale del dataset, no de la regla', () {
      final ultramarines =
          dataset.factionNamed('Imperium - Adeptus Astartes - Ultramarines');
      final porNombre = {
        for (final d in dataset.detachmentsOf(ultramarines)) d.name: d.disposiciones
      };
      expect(porNombre['Gladius Task Force'], ['Priority Assets']);
      expect(porNombre['Anvil Siege Force'], ['Take and Hold']);
      expect(porNombre['Stormlance Task Force'], ['Disruption']);
      expect(porNombre['Vanguard Spearhead'], ['Reconnaissance']);
    });

    test('y la tienen todos los detachments de las 36 facciones', () {
      final vistos = <String>{};
      final sin = <String>[];
      for (final faccion in dataset.factions) {
        for (final d in dataset.detachmentsOf(faccion)) {
          if (!vistos.add(d.id)) continue;
          if (d.disposiciones.isEmpty) sin.add('${faccion.name} · ${d.name}');
        }
      }
      expect(vistos.length, greaterThan(250));
      expect(sin, isEmpty);
    });
  });

  group('una miniatura suelta marca su equipo, no lo cuenta', () {
    test('un vehículo o un personaje es una miniatura; una escuadra no', () {
      final csm = listaDe('Chaos - Chaos Space Marines');
      final rhino = unidadDe(csm, 'Chaos Rhino');
      csm.add(rhino);
      expect(csm.esUnaSolaMiniatura(rhino), isTrue);

      final dg = listaDe('Chaos - Death Guard');
      final marines = unidadDe(dg, 'Plague Marines');
      dg.add(marines);
      expect(dg.esUnaSolaMiniatura(marines), isFalse);
      // El campeón sí: lo que cuelga de él lo lleva él solo.
      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');
      expect(dg.esUnaSolaMiniatura(campeon), isTrue);
    });

    test('y lo que ofrece es «lo lleva o no»: techo de uno', () {
      final csm = listaDe('Chaos - Chaos Space Marines');
      final rhino = unidadDe(csm, 'Chaos Rhino');
      csm.add(rhino);
      final havoc = csm.optionsFor(rhino).firstWhere((o) => o.name == 'Havoc launcher');
      expect(csm.effectiveMaxOf(rhino, havoc), 1);
      expect(csm.canAdd(rhino, havoc), isTrue);
    });
  });
}
