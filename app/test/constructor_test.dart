import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warorgan/src/datos/repositorio.dart';
import 'package:warorgan/src/estado/lista_en_curso.dart';
import 'package:warorgan/src/pantallas/anadir_unidad.dart';
import 'package:warorgan/src/pantallas/elegir_detachment.dart';
import 'package:warorgan/src/pantallas/lista.dart';
import 'package:warorgan/src/pantallas/listas.dart';
import 'package:warorgan/src/pantallas/unidad_en_lista.dart';
import 'package:warorgan/src/tema.dart';
import 'package:warorgan_core/warorgan_core.dart';

Directory _datos() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() {
  // Un toque que cae fuera de la pantalla solo saca un aviso por consola y el test sigue como si
  // nada. Eso hacía que un test verde no probara nada: tocaba el vacío. Aquí es un fallo.
  WidgetController.hitTestWarningShouldBeFatal = true;

  late Dataset dataset;
  late Faction deathGuard;

  setUpAll(() async {
    dataset = await Dataset.load(_datos(), notas: File('../data/wargear/notas-de-equipo.json'));
    deathGuard = dataset.factionNamed('Chaos - Death Guard');
  });

  BattleSize tamano(int puntos) =>
      dataset.battleSizes.firstWhere((t) => t.pointsLimit == puntos);

  ListaEnCurso nuevaLista({int puntos = 2000}) =>
      ListaEnCurso(dataset: dataset, faccion: deathGuard, tamano: tamano(puntos));

  Future<void> mostrar(WidgetTester tester, Widget pantalla) async {
    await tester.pumpWidget(Datos(
      dataset: dataset,
      child: MaterialApp(theme: Tema.oscuro, home: pantalla),
    ));
    await tester.pumpAndSettle();
  }

  /// Con la ventana alta, para lo que hay que ver de una vez.
  ///
  /// La ventana de prueba son 600 píxeles de alto y la lista es perezosa: lo que queda debajo ni
  /// se construye, así que no se puede buscar. Agrandarla comprueba lo que se quiere comprobar
  /// —que la pantalla lo enseña— en vez de ir arrastrando a ciegas.
  Future<void> conPantallaAlta(WidgetTester tester, Future<void> Function() prueba) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await prueba();
  }

  group('el estado de la lista', () {
    test('empieza vacía, sin detachment y por tanto ilegal', () {
      final lista = nuevaLista();
      expect(lista.puntos, 0);
      expect(lista.restantes, 2000);
      expect(lista.incumplimientos.map((v) => v.message),
          contains('Falta elegir un detachment'));
    });

    test('al añadir una unidad suma sus puntos con los mínimos ya puestos', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers'));
      expect(lista.puntos, 65);
      expect(lista.restantes, 1935);
      expect(lista.incumplimientos, isEmpty);
    });

    test('quitar una unidad devuelve los puntos', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers'));
      lista.quitarUnidad(lista.roster.units.first);
      expect(lista.puntos, 0);
    });

    test('equipar una mejora sube el precio y gasta presupuesto', () {
      final detachment = dataset
          .detachmentsOf(deathGuard)
          .firstWhere((d) => d.name == 'Virulent Vectorium');
      final lista = nuevaLista()..elegirDetachment(detachment);
      lista.anadirUnidad(
          deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));

      final principe = lista.roster.units.first;
      final base = lista.puntos;
      final mejora = lista
          .opcionesDe(principe)
          .firstWhere((o) => o.name == 'Daemon Weapon of Nurgle');
      lista.anadirOpcion(principe, mejora);

      expect(lista.puntos, base + 10);
      expect(lista.gastoDe(enhancementsCostTypeId), 1);
      expect(lista.cuantasHay(principe, mejora), 1);
    });

    test('quitar la última de una opción la borra, no la deja en cero', () {
      // Con miniaturas, que es lo que de verdad admite varias. Una mejora no vale: su grupo deja
      // elegir una sola y por eso se comporta como un botón de radio, no como un contador.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      final marines = lista.roster.units.first;
      final opcion = lista
          .opcionesDe(marines)
          .firstWhere((o) => o.name == 'Plague Marine w/ boltgun');

      // La escuadra ya trae cuatro de serie, así que se cuenta desde ahí.
      final deSerie = lista.cuantasHay(marines, opcion);
      expect(deSerie, 4, reason: 'el dataset marca el marine con bólter como equipo por defecto');

      lista.anadirOpcion(marines, opcion);
      lista.anadirOpcion(marines, opcion);
      expect(lista.cuantasHay(marines, opcion), deSerie + 2,
          reason: 'la segunda sube la cuenta, no duplica la fila');

      for (var i = 0; i < deSerie + 2; i++) {
        lista.quitarOpcion(marines, opcion);
      }
      expect(lista.cuantasHay(marines, opcion), 0);
      expect(marines.children.where((h) => h.entryId == opcion.entryId), isEmpty);
    });

    test('en un grupo de una sola opción, elegir sustituye en vez de apilar', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      final marines = lista.roster.units.first;
      final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');

      // El Campeón nace con sus Plague knives puestas. Elegir el Power fist tiene que quitarlas:
      // su grupo deja exactamente un arma, y apilarlas dejaba la unidad incumpliendo para siempre.
      final punio = lista.opcionesDe(campeon).firstWhere((o) => o.name == 'Power fist');
      lista.anadirOpcion(campeon, punio);

      final enEseGrupo = campeon.children.where((h) => h.groupId == punio.groupId);
      expect(enEseGrupo, hasLength(1));
      expect(enEseGrupo.first.name, 'Power fist');
    });

    test('señala en qué unidad está el problema, no solo que lo hay', () {
      // «Tu lista tiene 2 avisos» no sirve de nada si no dice cuál abrir. Los Blightlord
      // Terminators exigen entre 2 y 9 miniaturas; llegan con las suyas, y aquí se vacían para
      // provocar el incumplimiento, que es lo que pasa en cuanto el jugador las quita.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Beasts of Nurgle'))
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'));

      final sinProblema = lista.roster.units.first;
      final conProblema = lista.roster.units.last;
      final grupo = conProblema.groups
          .firstWhere((g) => g.name == '2-9 Blightlord Terminators');
      conProblema.children.removeWhere((c) => c.groupId == grupo.id);
      expect(lista.incumplimientosDe(sinProblema), isEmpty);
      expect(lista.incumplimientosDe(conProblema).map((v) => v.message).join(' '),
          contains('mínimo 2, hay 0'));
    });

    test('equipar la unidad hace desaparecer el aviso de ese grupo', () {
      // Solo el de ese grupo: la unidad tiene varios que rellenar —el Champion también elige
      // arma— y cada uno se apaga por su cuenta, que es como se termina de configurar.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'));
      final unidad = lista.roster.units.single;
      String avisos() => lista.incumplimientosDe(unidad).map((v) => v.message).join(' | ');

      // Se vacía el grupo para tener el aviso que se quiere ver apagarse.
      final vacio = unidad.groups.firstWhere((g) => g.name == '2-9 Blightlord Terminators');
      unidad.children.removeWhere((c) => c.groupId == vacio.id);
      expect(avisos(), contains('2-9 Blightlord Terminators'));

      final arma = lista
          .opcionesDe(unidad)
          .firstWhere((o) => o.groupName == '2-9 Blightlord Terminators');
      lista.anadirOpcion(unidad, arma);
      lista.anadirOpcion(unidad, arma);
      expect(avisos(), isNot(contains('2-9 Blightlord Terminators')));
    });

    test('deshacer devuelve la lista a como estaba, y rehacer la trae de vuelta', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      expect(lista.sePuedeDeshacer, isTrue);

      lista.anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers'));
      final conUnidad = lista.puntos;
      expect(lista.roster.units, hasLength(1));

      lista.deshacer();
      expect(lista.roster.units, isEmpty);
      expect(lista.sePuedeRehacer, isTrue);

      lista.rehacer();
      expect(lista.roster.units, hasLength(1));
      expect(lista.puntos, conUnidad);
    });

    test('una unidad puede llevar nombre propio, y se guarda con la lista', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'));
      final unidad = lista.roster.units.single;
      lista.renombrarUnidad(unidad, 'La Guardia Podrida');

      expect(unidad.displayName, 'La Guardia Podrida');
      expect(unidad.name, 'Blightlord Terminators', reason: 'el de la hoja no se pierde');

      final vuelta = Guardado.deTexto(dataset, lista.paraGuardar).roster;
      expect(vuelta.units.single.customName, 'La Guardia Podrida');
    });

    test('las uniones sobreviven al guardado', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'))
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Lord of Virulence'));
      final blight = lista.roster.units.first;
      final lord = lista.roster.units.last;
      lista.unir(lord, blight);

      final vuelta = Guardado.deTexto(dataset, lista.paraGuardar).roster;
      final lordVuelto = vuelta.units.firstWhere((u) => u.name == 'Lord of Virulence');
      expect(lordVuelto.attachedTo?.name, 'Blightlord Terminators');
    });

    test('el catálogo se agrupa por rol y se puede filtrar por lo que cabe', () {
      final lista = nuevaLista(puntos: 1000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      final porRol = lista.catalogoPorRol();
      expect(porRol, isNotEmpty);
      expect(porRol.map((g) => g.rol), contains('Character'));

      // Con casi nada de presupuesto, el filtro deja fuera lo caro.
      lista.anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Mortarion'));
      final caben = lista.catalogoPorRol(soloLasQueCaben: true)
          .expand((g) => g.unidades)
          .toList();
      final todas = lista.catalogoPorRol().expand((g) => g.unidades).toList();
      expect(caben.length, lessThan(todas.length));
      expect(caben.every((u) => (u.points ?? 0) <= lista.restantes), isTrue);
    });

    test('el selector no ofrece unidades que la lista no puede llevar', () {
      // Lo que motivó todo esto: los demonios de Nurgle salían en cualquier lista de Death Guard,
      // y el dataset dice que solo entran con Tallyband Summoners.
      ListaEnCurso con(String detachment) => nuevaLista()
        ..elegirDetachment(dataset
            .detachmentsOf(deathGuard)
            .firstWhere((d) => d.name == detachment));

      final virulent = con('Virulent Vectorium').unidadesDisponibles.map((u) => u.name);
      final tallyband = con('Tallyband Summoners').unidadesDisponibles.map((u) => u.name);

      expect(virulent, isNot(contains('Plaguebearers')));
      expect(tallyband, contains('Plaguebearers'));
      expect(virulent, contains('Plague Marines'), reason: 'lo suyo sí, claro');
    });

    test('los interruptores de contenido encienden y apagan lo que se ofrece', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      bool hayLegends() =>
          lista.unidadesDisponibles.any((u) => u.name.contains('[Legends]'));

      expect(hayLegends(), isFalse, reason: 'apagados por defecto, como en el dataset');
      final legends = lista.interruptores.firstWhere((o) => o.name == 'Show Legends');
      lista.cambiarInterruptor(legends.id, true);
      expect(hayLegends(), isTrue);
      lista.cambiarInterruptor(legends.id, false);
      expect(hayLegends(), isFalse);
    });

    test('no se ofrece material de Crusade en una lista de partida normal', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'));
      final grupos =
          lista.opcionesDe(lista.roster.units.single).map((o) => o.groupName).toSet();
      expect(grupos, isNot(contains('Battle Tallies')));
      expect(grupos, isNot(contains('Weapon Modifications')));
      expect(grupos, contains('2-9 Blightlord Terminators'));
    });

    test('el tamaño de partida cambia lo que la lista da por legal', () {
      final poxwalkers = deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers');
      bool legalCon(int puntos, int copias) {
        final lista = nuevaLista(puntos: puntos)
          ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
        for (var i = 0; i < copias; i++) {
          lista.anadirUnidad(poxwalkers);
        }
        return lista.incumplimientos.isEmpty;
      }

      expect(legalCon(2000, 3), isTrue, reason: 'en Strike Force caben tres');
      expect(legalCon(1000, 3), isFalse, reason: 'en Incursion solo dos');
      expect(legalCon(1000, 2), isTrue);
    });
  });

  group('las pantallas', () {
    testWidgets('una lista nueva se crea eligiendo tamaño y facción', (tester) async {
      await mostrar(tester, PantallaDeNuevaLista(dataset: dataset));
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('Crear lista'), findsOneWidget);

      // Sin facción no se puede crear.
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await tester.tap(find.text('1000'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
          find.text('Death Guard'), find.byType(ListView).last, const Offset(0, -80));
      await tester.tap(find.text('Death Guard'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('la lista enseña puntos, aviso de detachment y unidades', (tester) async {
      final lista = nuevaLista();
      await mostrar(tester, PantallaDeLista(lista: lista));

      expect(find.text(' / 2000 pts'), findsOneWidget);
      expect(find.text('0'), findsWidgets, reason: 'el marcador arranca a cero');
      expect(find.text('Sin elegir'), findsOneWidget);
      expect(find.textContaining('Falta elegir un detachment'), findsOneWidget);

      lista.elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      lista.anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers'));
      await tester.pumpAndSettle();

      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Poxwalkers'), findsOneWidget);
      expect(find.text('65 pts'), findsOneWidget);
    });

    testWidgets('elegir detachment enseña su regla y sus mejoras', (tester) async {
      final lista = nuevaLista();
      await mostrar(tester, PantallaDeElegirDetachment(lista: lista));

      // La regla y las mejoras siguen a un toque, detrás de la flecha, para comparar antes de
      // decidir; pero ya no hay que desplegarlas para poder elegir.
      final ficha = find.ancestor(
          of: find.text('Virulent Vectorium'), matching: find.byType(ExpansionTile));
      await tester.tap(find.descendant(of: ficha, matching: find.byIcon(Icons.expand_more)));
      await tester.pumpAndSettle();
      expect(find.text('MEJORAS'), findsOneWidget);
      expect(find.textContaining('Daemon Weapon of Nurgle'), findsOneWidget);
    });

    testWidgets('un detachment se elige de un toque, sin desplegar ni buscar un botón',
        (tester) async {
      final lista = nuevaLista();
      await mostrar(tester, PantallaDeElegirDetachment(lista: lista));

      await tester.tap(find.text('Virulent Vectorium'));
      await tester.pumpAndSettle();
      expect(lista.roster.detachment!.name, 'Virulent Vectorium');

      // Y se quita igual, volviendo a tocarlo.
      await tester.tap(find.text('Virulent Vectorium'));
      await tester.pumpAndSettle();
      expect(lista.roster.detachments, isEmpty);
    });

    testWidgets('caben varios detachments mientras quepan sus Detachment Points',
        (tester) async {
      // A 2000 puntos el presupuesto es de 3 DP. Tallyband Summoners cuesta 2, así que queda uno
      // por gastar y tiene que poder gastarse; lo que no cabe es un tercero.
      final lista = nuevaLista(puntos: 2000);
      await mostrar(tester, PantallaDeElegirDetachment(lista: lista));
      expect(find.text('0/3 DP'), findsOneWidget);

      Future<void> anadir(String nombre) async {
        await tester.ensureVisible(find.text(nombre));
        await tester.pumpAndSettle();
        await tester.tap(find.text(nombre));
        await tester.pumpAndSettle();
      }

      await anadir('Tallyband Summoners');
      expect(lista.puntosDeDetachment.gastados, 2);
      expect(find.text('2/3 DP'), findsOneWidget);

      await anadir('Contagion Engines');
      expect(lista.roster.detachments, hasLength(2));
      expect(find.text('3/3 DP'), findsOneWidget);
      expect(lista.incumplimientos.map((v) => v.message).join(' '),
          isNot(contains('máximo')));

      // El siguiente ya no cabe: su botón lo dice y no hace nada.
      expect(lista.cabeDetachment(
          lista.detachmentsDisponibles.firstWhere((d) => d.name == 'Flyblown Host')),
          isFalse);
    });

    testWidgets('al añadir unidades se avisa de las que ya no caben', (tester) async {
      final lista = nuevaLista(puntos: 1000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      await mostrar(tester, PantallaDeAnadirUnidad(lista: lista));

      await tester.enterText(find.byType(TextField), 'poxwalkers');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      // Tocar la fila abre la hoja de datos; lo que añade es el «+». Eran la misma cosa y no lo
      // son: se toca para saber qué es una unidad mucho más a menudo que para meterla.
      final poxwalkers =
          lista.unidadesDisponibles.firstWhere((u) => u.name == 'Poxwalkers');
      await tester.tap(find.byKey(ValueKey('anadir-${poxwalkers.id}')));
      await tester.pumpAndSettle();
      expect(lista.roster.units, hasLength(1));

      // Y la pantalla sigue abierta: una lista se monta de diez en diez, no de una en una.
      expect(find.byType(PantallaDeAnadirUnidad), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('anadir-${poxwalkers.id}')));
      await tester.pumpAndSettle();
      expect(lista.roster.units, hasLength(2));
    });

    testWidgets('tocar una unidad del catálogo enseña su hoja, no la añade', (tester) async {
      final lista = nuevaLista(puntos: 1000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      await mostrar(tester, PantallaDeAnadirUnidad(lista: lista));

      await tester.enterText(find.byType(TextField), 'poxwalkers');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poxwalkers'));
      await tester.pumpAndSettle();

      expect(lista.roster.units, isEmpty, reason: 'mirar no es añadir');
      expect(find.text('CARACTERÍSTICAS'.toUpperCase()), findsNothing);
      expect(find.text('POXWALKERS'), findsWidgets, reason: 'se ha abierto su hoja');
    });

    testWidgets('cambiar un arma no hace crecer la escuadra: se la quita a una',
        (tester) async {
      // Era el fallo de fondo: el arma y la miniatura competían por el mismo hueco, así que con
      // la escuadra llena no se podía asignar ni un arma especial.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      final marines = lista.roster.units.first;
      final escuadra =
          marines.groups.firstWhere((g) => lista.esGrupoDeMiniaturas(marines, g));

      // Se llena hasta el tope antes de tocar nada, que es donde antes se atascaba.
      while (lista.cabeOtraMiniatura(marines, escuadra)) {
        lista.anadirMiniatura(marines, escuadra);
      }
      final miniaturas = lista.usoDeGrupo(marines, escuadra).puestas;
      final puntos = lista.puntos;
      expect(miniaturas, 9);

      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: marines));

      final lanzador = lista
          .opcionesDe(marines)
          .firstWhere((o) => o.name == 'Plague Marine w/ blight launcher');
      final fila = find.byKey(ValueKey('arma-${lanzador.entryId}'));
      await tester.dragUntilVisible(fila, find.byType(ListView).first, const Offset(0, -80));
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: fila, matching: find.byIcon(Icons.add)));
      await tester.pumpAndSettle();

      expect(lista.cuantasHay(marines, lanzador), 1);
      expect(lista.usoDeGrupo(marines, escuadra).puestas, miniaturas,
          reason: 'la escuadra sigue siendo de nueve');
      expect(lista.puntos, puntos, reason: 'y cuesta lo mismo: no hay una miniatura más');

      // Y el «−» le devuelve el bólter.
      await tester.tap(find.descendant(of: fila, matching: find.byIcon(Icons.remove)));
      await tester.pumpAndSettle();
      expect(lista.cuantasHay(marines, lanzador), 0);
      expect(lista.usoDeGrupo(marines, escuadra).puestas, miniaturas);
    });

    testWidgets('la pantalla enseña las opciones con las palabras de la hoja',
        (tester) async {
      // «For every 5 models in this unit, 1 Plague Marine's plague boltgun can be replaced…».
      // BSData no trae esa frase: escribe la misma regla como un techo que sube al crecer la
      // escuadra. Las dos cosas hacen falta y hacen cosas distintas.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      final marines = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: marines));

      expect(find.text('OPCIONES DE EQUIPO DE LA HOJA'), findsOneWidget);
      expect(find.textContaining('For every 5 models in this unit'), findsWidgets);
      expect(find.textContaining('blight launcher'), findsWidgets);
    });

    testWidgets('y no la enseña donde el texto ya no vale', (tester) async {
      // El Defiler de las index cards de 10ª llevaba otras armas; ahí solo se enseñan los topes.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Defiler'));
      await mostrar(tester,
          PantallaDeUnidadEnLista(lista: lista, unidad: lista.roster.units.first));

      expect(find.text('OPCIONES DE EQUIPO DE LA HOJA'), findsNothing);
    });

    testWidgets('y dice a cuántas miniaturas se les puede cambiar el arma',
        (tester) async {
      await conPantallaAlta(tester, () async {
        final lista = nuevaLista()
          ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
          ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
        final marines = lista.roster.units.first;
        await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: marines));

        // El número es el efectivo de ahora, no el declarado: el dataset escribe «una por cada
        // cinco miniaturas» como un techo que sube al crecer la escuadra.
        expect(find.textContaining('Cambia el arma de'), findsWidgets);
        expect(find.text('4 Plague Marines'), findsOneWidget,
            reason: 'y el contador dice cuántas hay, sin el «4-9» del nombre del grupo');
      });
    });

    testWidgets('una mejora se elige marcándola, porque solo cabe una', (tester) async {
      final lista = nuevaLista()
        ..elegirDetachment(dataset
            .detachmentsOf(deathGuard)
            .firstWhere((d) => d.name == 'Virulent Vectorium'))
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
      final principe = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: principe));

      expect(find.text('ENHANCEMENTS'), findsOneWidget);
      // El nombre sale dos veces: en el editor y, más abajo, en la hoja de datos. Se toca el del
      // editor, que es el primero.
      await tester.dragUntilVisible(find.text('Daemon Weapon of Nurgle').first,
          find.byType(ListView).first, const Offset(0, -80));
      await tester.tap(find.text('Daemon Weapon of Nurgle').first);
      await tester.pumpAndSettle();

      final arma = lista
          .opcionesDe(principe)
          .firstWhere((o) => o.name == 'Daemon Weapon of Nurgle');
      expect(lista.cuantasHay(principe, arma), 1);

      // Y se vuelve a pulsar para quitarla: una casilla que solo sabe marcar deja atrapado al
      // jugador, que no puede deshacer una mejora que eligió sin querer.
      await tester.tap(find.text('Daemon Weapon of Nurgle').first);
      await tester.pumpAndSettle();
      expect(lista.cuantasHay(principe, arma), 0);
    });

    testWidgets('el editor de una unidad enseña también su hoja de datos', (tester) async {
      // Ver y editar en la misma pantalla: al elegir un arma hace falta saber qué hace, y salir a
      // otra pantalla a mirarlo es perder el sitio.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
      final marines = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: marines));

      expect(find.text('COMPOSICIÓN Y EQUIPO'), findsOneWidget);
      await tester.dragUntilVisible(find.text('ARMAS A DISTANCIA'),
          find.byType(ListView).first, const Offset(0, -200));
      expect(find.text('HABILIDADES'), findsOneWidget);
      expect(find.text('PALABRAS CLAVE'), findsOneWidget);
    });

    testWidgets('se llega al equipo del campeón, que vive dos niveles más abajo',
        (tester) async {
      await conPantallaAlta(tester, () async {
        final lista = nuevaLista()
          ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
          ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Plague Marines'));
        final marines = lista.roster.units.first;
        final campeon = marines.children.firstWhere((c) => c.name == 'Plague Champion');
        await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: marines));

        // Llega con su equipo de serie y sale una sola vez, no como opción y además como fila.
        expect(campeon.children.map((c) => c.name), containsAll(['Plague knives', 'Boltgun']));
        expect(find.text('Plague Champion'), findsOneWidget);

        // Su equipo vive dos niveles por debajo de la unidad. La pantalla vieja pintaba un solo
        // nivel, así que esto no existía en ninguna parte y no había forma de cambiar el arma.
        await tester.tap(find.text('Plague Champion'));
        await tester.pumpAndSettle();

        final punio = lista.opcionesDe(campeon).firstWhere((o) => o.name == 'Power fist');
        final fila = find.byKey(ValueKey('opcion-${punio.entryId}-${punio.groupId}'));
        await tester.ensureVisible(fila);
        await tester.pumpAndSettle();
        await tester.tap(fila);
        await tester.pumpAndSettle();

        expect(campeon.children.map((c) => c.name), contains('Power fist'),
            reason: 'el arma del Campeón tiene que poder cambiarse desde la pantalla');
        expect(campeon.children.map((c) => c.name), isNot(contains('Plague knives')),
            reason: 'y sustituir a la que traía, que su grupo deja un arma sola');
      });
    });

    testWidgets('la misma arma en dos grupos marca una casilla, no dos', (tester) async {
      // El Defiler ofrece el Electroscourge dos veces: para sustituir el lanzamisiles y para
      // sustituir el baleflamer, y es la misma entrada del dataset. Pasa en 295 unidades.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Defiler'));
      final defiler = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: defiler));

      final dosVeces = lista
          .opcionesDe(defiler)
          .where((o) => o.name == 'Electroscourge')
          .toList();
      expect(dosVeces, hasLength(2));

      final fila = find
          .byKey(ValueKey('opcion-${dosVeces.first.entryId}-${dosVeces.first.groupId}'));
      await tester.scrollUntilVisible(fila, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.pumpAndSettle();

      expect(lista.cuantasHay(defiler, dosVeces.first), 1);
      expect(lista.cuantasHay(defiler, dosVeces.last), 0,
          reason: 'el otro grupo sigue con lo suyo');
    });

    testWidgets('un arma obligatoria no se puede desmarcar y dejar el hueco vacío',
        (tester) async {
      // Era lo que ponía «el baleflamer es obligatorio» en el Defiler: se desmarcaba el arma que
      // el dataset exige y salía el aviso de un hueco que el jugador no sabía que había abierto.
      // Un arma no es obligatoria; elegir una de las cuatro, sí.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Defiler'));
      final defiler = lista.roster.units.first;
      expect(lista.incumplimientosDe(defiler), isEmpty, reason: 'entra legal');
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: defiler));

      final baleflamer = lista
          .opcionesDe(defiler)
          .firstWhere((o) => o.name == 'Heavy baleflamer');
      final fila = find
          .byKey(ValueKey('opcion-${baleflamer.entryId}-${baleflamer.groupId}'));
      await tester.scrollUntilVisible(fila, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.pumpAndSettle();

      expect(lista.cuantasHay(defiler, baleflamer), 1,
          reason: 'sigue puesta: pulsar elige, no desmarca');
      expect(lista.incumplimientosDe(defiler), isEmpty,
          reason: 'y no aparece ningún aviso de arma obligatoria');
    });

    testWidgets('el equipo fijo se enseña bloqueado, sin contador que baje a cero',
        (tester) async {
      // Las Shearing claws del Defiler son `min 1, max 1`: las lleva y punto.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Defiler'));
      final defiler = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: defiler));

      final garras =
          lista.opcionesDe(defiler).firstWhere((o) => o.name == 'Shearing claws');
      final fila = find.byKey(ValueKey('opcion-${garras.entryId}-${garras.groupId}'));
      await tester.scrollUntilVisible(fila, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();

      expect(find.descendant(of: fila, matching: find.byIcon(Icons.lock_outline)),
          findsOneWidget);
      expect(find.descendant(of: fila, matching: find.byIcon(Icons.remove)), findsNothing,
          reason: 'no hay nada que quitar: no es una elección');
    });

    testWidgets('la escuadra tiene un contador de miniaturas, no uno por arma',
        (tester) async {
      // Primero se decide si son cinco o diez y después con qué van. Repartir el tamaño entre las
      // armas obliga a sumar de cabeza para saber cuántas miniaturas hay.
      final lista = nuevaLista(puntos: 2000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Poxwalkers'));
      final pox = lista.roster.units.first;
      final grupo = pox.groups.firstWhere((g) => g.name!.contains('Poxwalkers'));
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: pox));

      expect(find.text('10 Poxwalkers'), findsOneWidget,
          reason: 'sin el «10-20» del nombre del grupo, que ya lo dice el contador');
      expect(lista.puntos, 65);

      await tester.tap(find.byKey(const ValueKey('anadir-miniatura')));
      await tester.pumpAndSettle();
      expect(lista.usoDeGrupo(pox, grupo).puestas, 11);
      expect(find.text('11 Poxwalkers'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quitar-miniatura')));
      await tester.pumpAndSettle();
      expect(lista.usoDeGrupo(pox, grupo).puestas, 10);
    });

    testWidgets('una escuadra de tamaño fijo no ofrece botones que no hacen nada',
        (tester) async {
      // «90 puntos son 5 miniaturas y punto»: ahí no hay nada que decidir, así que no hay botones.
      final lista = nuevaLista(puntos: 2000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      final defiler = deathGuard.units.firstWhere((u) => u.name == 'Defiler');
      lista.anadirUnidad(defiler);
      await mostrar(tester,
          PantallaDeUnidadEnLista(lista: lista, unidad: lista.roster.units.first));

      expect(find.byKey(const ValueKey('anadir-miniatura')), findsNothing,
          reason: 'el Defiler es una sola miniatura');
    });

    testWidgets('el botón de Legends enciende y apaga el contenido retirado',
        (tester) async {
      final lista = nuevaLista(puntos: 2000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      await mostrar(tester, PantallaDeAnadirUnidad(lista: lista));

      final antes = lista.unidadesDisponibles.length;
      expect(lista.unidadesDisponibles.where((u) => u.name.contains('[Legends]')),
          isEmpty,
          reason: 'de serie no se ofrecen: son hojas retiradas');

      await tester.tap(find.byKey(const ValueKey('boton-legends')));
      await tester.pumpAndSettle();

      expect(lista.unidadesDisponibles.length, greaterThan(antes));
      expect(lista.unidadesDisponibles.where((u) => u.name.contains('[Legends]')),
          isNotEmpty);
    });

    testWidgets('los aliados salen en su sección, no entre los personajes propios',
        (tester) async {
      // Los Chaos Knights no son de la Death Guard. Mezclarlos en Personajes y Vehículos junto a
      // los propios es meter dos cosas distintas en el mismo cajón.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      await mostrar(tester, PantallaDeAnadirUnidad(lista: lista));

      final secciones = lista.catalogoPorRol();
      expect(secciones.map((s) => s.rol), contains('Aliados · Chaos Knights'));

      final aliados =
          secciones.firstWhere((s) => s.rol == 'Aliados · Chaos Knights').unidades;
      expect(aliados.map((u) => u.name), contains('Knight Abominant'));

      // Y no está además entre los propios.
      for (final seccion in secciones.where((s) => !s.rol.startsWith('Aliados'))) {
        expect(seccion.unidades.map((u) => u.name), isNot(contains('Knight Abominant')));
      }
    });
  });
}
