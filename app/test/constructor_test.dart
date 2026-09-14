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
  late Dataset dataset;
  late Faction deathGuard;

  setUpAll(() async {
    dataset = await Dataset.load(_datos());
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
      expect(lista.cuantasHay(principe, mejora.entryId), 1);
    });

    test('quitar la última de una opción la borra, no la deja en cero', () {
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
      final principe = lista.roster.units.first;
      final opcion = lista.opcionesDe(principe).firstWhere((o) => o.basePointsEach > 0);

      lista.anadirOpcion(principe, opcion);
      lista.anadirOpcion(principe, opcion);
      expect(lista.cuantasHay(principe, opcion.entryId), 2,
          reason: 'la segunda sube la cuenta, no duplica la fila');

      lista.quitarOpcion(principe, opcion.entryId);
      lista.quitarOpcion(principe, opcion.entryId);
      expect(lista.cuantasHay(principe, opcion.entryId), 0);
      expect(principe.children.where((h) => h.entryId == opcion.entryId), isEmpty);
    });

    test('señala en qué unidad está el problema, no solo que lo hay', () {
      // «Tu lista tiene 2 avisos» no sirve de nada si no dice cuál abrir. Los Blightlord
      // Terminators exigen elegir entre 2 y 9 miniaturas, y nacen sin ninguna elegida.
      final lista = nuevaLista()
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first)
        ..anadirUnidad(deathGuard.units.firstWhere((u) => u.name == 'Beasts of Nurgle'))
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Blightlord Terminators'));

      final sinProblema = lista.roster.units.first;
      final conProblema = lista.roster.units.last;
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
      expect(avisos(), contains('2-9 Blightlord Terminators'));

      final arma = lista
          .opcionesDe(unidad)
          .firstWhere((o) => o.groupName == '2-9 Blightlord Terminators');
      lista.anadirOpcion(unidad, arma);
      lista.anadirOpcion(unidad, arma);
      expect(avisos(), isNot(contains('2-9 Blightlord Terminators')));
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

      await tester.tap(find.text('Virulent Vectorium'));
      await tester.pumpAndSettle();
      expect(find.text('MEJORAS'), findsOneWidget);
      expect(find.textContaining('Daemon Weapon of Nurgle'), findsOneWidget);

      await tester.tap(find.text('Elegir este detachment'));
      await tester.pumpAndSettle();
      expect(lista.roster.detachment!.name, 'Virulent Vectorium');
    });

    testWidgets('al añadir unidades se avisa de las que ya no caben', (tester) async {
      final lista = nuevaLista(puntos: 1000)
        ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
      await mostrar(tester, PantallaDeAnadirUnidad(lista: lista));

      await tester.enterText(find.byType(TextField), 'poxwalkers');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      await tester.tap(find.text('Poxwalkers'));
      await tester.pumpAndSettle();
      expect(lista.roster.units, hasLength(1));
    });

    testWidgets('las opciones de una unidad se suman y se restan', (tester) async {
      final lista = nuevaLista()
        ..elegirDetachment(dataset
            .detachmentsOf(deathGuard)
            .firstWhere((d) => d.name == 'Virulent Vectorium'))
        ..anadirUnidad(
            deathGuard.units.firstWhere((u) => u.name == 'Daemon Prince of Nurgle'));
      final principe = lista.roster.units.first;
      await mostrar(tester, PantallaDeUnidadEnLista(lista: lista, unidad: principe));

      expect(find.text('ENHANCEMENTS'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Daemon Weapon of Nurgle'),
          find.byType(ListView), const Offset(0, -80));

      final fila = find.ancestor(
          of: find.text('Daemon Weapon of Nurgle'), matching: find.byType(Row));
      await tester.tap(find.descendant(of: fila.first, matching: find.byIcon(Icons.add)));
      await tester.pumpAndSettle();
      expect(lista.cuantasHay(principe, lista
          .opcionesDe(principe)
          .firstWhere((o) => o.name == 'Daemon Weapon of Nurgle')
          .entryId), 1);
    });
  });
}
