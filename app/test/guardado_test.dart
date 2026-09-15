import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warorgan/src/datos/almacen.dart';
import 'package:warorgan/src/datos/repositorio.dart';
import 'package:warorgan/src/estado/lista_en_curso.dart';
import 'package:warorgan/src/pantallas/exportar.dart';
import 'package:warorgan/src/pantallas/listas.dart';
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
    dataset = await Dataset.load(_datos());
    deathGuard = dataset.factionNamed('Chaos - Death Guard');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ListaEnCurso listaConUnidad() {
    final lista = ListaEnCurso(
      dataset: dataset,
      faccion: deathGuard,
      tamano: dataset.battleSizes.firstWhere((b) => b.pointsLimit == 2000),
    )
      ..renombrar('Los Segadores')
      ..elegirDetachment(dataset.detachmentsOf(deathGuard).first);
    lista.anadirUnidad(
        lista.unidadesDisponibles.firstWhere((u) => u.name == 'Plague Marines'));
    return lista;
  }

  group('el almacén', () {
    test('lo guardado se vuelve a montar igual', () async {
      final almacen = await Almacen.abrir();
      final lista = listaConUnidad();
      await almacen.escribir([lista.paraGuardar]);

      final otro = await Almacen.abrir();
      final recuperadas = otro.recuperar(dataset);
      expect(recuperadas.ilegibles, 0);
      expect(recuperadas.listas, hasLength(1));

      final vuelta = recuperadas.listas.single.roster;
      expect(vuelta.name, 'Los Segadores');
      expect(vuelta.points, lista.puntos);
      expect(vuelta.units.single.name, 'Plague Marines');
    });

    test('una lista ilegible no se lleva por delante a las demás', () async {
      final almacen = await Almacen.abrir();
      await almacen.escribir(['{esto no es json', listaConUnidad().paraGuardar]);

      final recuperadas = (await Almacen.abrir()).recuperar(dataset);
      expect(recuperadas.ilegibles, 1);
      expect(recuperadas.listas, hasLength(1), reason: 'la buena se monta igual');
    });

    test('sin nada guardado no hay listas y no se rompe', () async {
      final recuperadas = (await Almacen.abrir()).recuperar(dataset);
      expect(recuperadas.listas, isEmpty);
      expect(recuperadas.ilegibles, 0);
    });
  });

  group('las pantallas', () {
    Future<void> mostrar(WidgetTester tester, Widget pantalla) async {
      await tester.pumpWidget(Datos(
        dataset: dataset,
        child: MaterialApp(theme: Tema.oscuro, home: pantalla),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('las listas guardadas salen al abrir la app', (tester) async {
      SharedPreferences.setMockInitialValues({
        'listas': [listaConUnidad().paraGuardar],
      });
      await mostrar(tester, const PantallaDeListas());

      // La tarjeta enseña lo que se mira al elegir qué lista abrir: nombre, facción, detachment
      // y puntos.
      expect(find.text('Los Segadores'), findsOneWidget);
      expect(find.text('Death Guard'), findsOneWidget);
      expect(find.textContaining('/2000 pts'), findsOneWidget);
    });

    testWidgets('exportar enseña la lista en texto plano, con sus avisos', (tester) async {
      await mostrar(tester, PantallaDeExportar(lista: listaConUnidad()));
      expect(find.textContaining('Los Segadores'), findsOneWidget);
      expect(find.textContaining('Plague Marines'), findsOneWidget);
      expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    });

    testWidgets('copiar deja la lista en el portapapeles', (tester) async {
      final lista = listaConUnidad();
      String? copiado;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiado = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      await mostrar(tester, PantallaDeExportar(lista: lista));
      await tester.tap(find.byIcon(Icons.copy_all_outlined));
      await tester.pumpAndSettle();
      expect(copiado, lista.comoTexto);
    });
  });
}
