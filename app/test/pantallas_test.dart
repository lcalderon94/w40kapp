import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warorgan/src/datos/repositorio.dart';
import 'package:warorgan/src/pantallas/facciones.dart';
import 'package:warorgan/src/pantallas/unidad.dart';
import 'package:warorgan/src/pantallas/unidades.dart';
import 'package:warorgan/src/pantallas/wiki.dart';
import 'package:warorgan/src/tema.dart';
import 'package:warorgan_core/warorgan_core.dart';

/// Las pruebas leen el dataset del disco, no de los assets: en un test no hay assets empaquetados
/// y lo que se quiere comprobar es que las pantallas saben pintar el dato real, que es donde se
/// rompen las cosas. El empaquetado lo cubre el propio build.
Directory _datos() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() {
  // Un toque que cae fuera de la pantalla solo saca un aviso por consola y el test sigue como si
  // nada. Eso hacía que un test verde no probara nada: tocaba el vacío. Aquí es un fallo.
  WidgetController.hitTestWarningShouldBeFatal = true;

  late Dataset dataset;

  setUpAll(() async => dataset = await Dataset.load(_datos()));

  Future<void> mostrar(WidgetTester tester, Widget pantalla) async {
    await tester.pumpWidget(Datos(
      dataset: dataset,
      child: MaterialApp(theme: Tema.oscuro, home: pantalla),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('las facciones salen agrupadas por bando', (tester) async {
    await mostrar(tester, const PantallaDeFacciones());
    expect(find.text('IMPERIUM'), findsOneWidget);
    expect(find.text('Death Guard'), findsOneWidget,
        reason: 'se enseña el nombre corto, no «Chaos - Death Guard»');
  });

  testWidgets('de una facción se llega a sus unidades y se pueden buscar', (tester) async {
    final deathGuard = dataset.factionNamed('Chaos - Death Guard');
    await mostrar(tester, PantallaDeUnidades(faccion: deathGuard));

    // Una facción pasa de las cien unidades, así que se busca en vez de bajar a mano.
    await tester.enterText(find.byType(TextField), 'poxwalkers');
    await tester.pumpAndSettle();
    expect(find.text('Poxwalkers'), findsOneWidget);
    expect(find.text('65 pts'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'typhus');
    await tester.pumpAndSettle();
    expect(find.text('Typhus'), findsOneWidget);
    expect(find.text('Poxwalkers'), findsNothing);
  });

  testWidgets('la búsqueda de unidades ignora tildes y mayúsculas', (tester) async {
    await mostrar(tester, PantallaDeUnidades(faccion: dataset.factionNamed('Xenos - Necrons')));
    await tester.enterText(find.byType(TextField), 'NECRON');
    await tester.pumpAndSettle();
    expect(find.textContaining('Necron'), findsWidgets);
  });

  testWidgets('la ficha de una unidad trae características, habilidades y armas', (tester) async {
    final deathGuard = dataset.factionNamed('Chaos - Death Guard');
    final typhus = deathGuard.units.firstWhere((u) => u.name == 'Typhus');
    await mostrar(tester, PantallaDeUnidad(unidad: typhus, faccion: deathGuard));

    // La línea de características, que es lo que se consulta cada turno. Las etiquetas van en
    // mayúsculas, como en la hoja impresa.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('SV'), findsOneWidget);
    expect(find.text('OC'), findsOneWidget);

    // El nombre va en la banda de cabecera, en mayúsculas. Sale más de una vez porque «Typhus»
    // es además una de sus palabras clave.
    expect(find.text('TYPHUS'), findsWidgets);
    expect(find.text('100 pts'), findsOneWidget);
    expect(find.text('HABILIDADES'), findsOneWidget);

    // El de fuera: las tablas de armas traen el suyo propio para poder desplazarse en horizontal.
    await tester.scrollUntilVisible(find.text('ARMAS DE CUERPO A CUERPO'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Lakrimae'), findsWidgets);
  });

  testWidgets('las armas pierden la flecha con que las marca el dataset', (tester) async {
    final deathGuard = dataset.factionNamed('Chaos - Death Guard');
    final typhus = deathGuard.units.firstWhere((u) => u.name == 'Typhus');
    await mostrar(tester, PantallaDeUnidad(unidad: typhus, faccion: deathGuard));
    // El de fuera: las tablas de armas traen el suyo propio para poder desplazarse en horizontal.
    await tester.scrollUntilVisible(find.text('ARMAS DE CUERPO A CUERPO'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('➤'), findsNothing);
    expect(find.textContaining('Lakrimae'), findsWidgets);
  });

  testWidgets('la wiki trae el glosario y se puede buscar', (tester) async {
    await mostrar(tester, const PantallaDeWiki());
    expect(find.text('Anti'), findsOneWidget, reason: 'ordenadas por nombre');

    await tester.enterText(find.byType(TextField), 'sustained');
    await tester.pumpAndSettle();
    expect(find.text('Sustained Hits'), findsOneWidget);
    expect(find.text('Anti'), findsNothing);
  });

  testWidgets('la wiki busca también dentro del texto de la regla', (tester) async {
    // Es como se usa de verdad: no te acuerdas del nombre de la regla, te acuerdas de lo que hace.
    await mostrar(tester, const PantallaDeWiki());
    await tester.enterText(find.byType(TextField), 'herida crítica');
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsWidgets);
  });

  testWidgets('una regla de la wiki se despliega con su texto traducido', (tester) async {
    await mostrar(tester, const PantallaDeWiki());
    await tester.enterText(find.byType(TextField), 'devastating');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Devastating Wounds'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cada vez'), findsWidgets);
  });
}
