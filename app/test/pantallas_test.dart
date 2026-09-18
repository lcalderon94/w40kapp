import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warorgan/src/datos/repositorio.dart';
import 'package:warorgan/src/pantallas/buscar.dart';
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

  setUpAll(() async => dataset = await Dataset.load(_datos(), notas: File('../data/wargear/notas-de-equipo.json')));

  Future<void> mostrar(WidgetTester tester, Widget pantalla) async {
    await tester.pumpWidget(Datos(
      dataset: dataset,
      child: MaterialApp(theme: Tema.oscuro, home: pantalla),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('las facciones salen por familia, y los capítulos juntos', (tester) async {
    await mostrar(tester, const PantallaDeFacciones());

    // Cuatro bloques y dentro los botones: se ve todo de golpe y se elige de un toque, en vez de
    // recorrer treinta y seis filas. Los doce capítulos de Space Marines van en su propio bloque,
    // no sueltos entre las dieciséis facciones del Imperium.
    expect(find.text('CHAOS'), findsOneWidget);
    expect(find.text('IMPERIUM'), findsOneWidget);
    expect(find.text('SPACE MARINES'), findsOneWidget);
    expect(find.text('Death Guard'), findsOneWidget,
        reason: 'se enseña el nombre corto, no «Chaos - Death Guard»');

    await tester.dragUntilVisible(
        find.text('XENOS'), find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('XENOS'), findsOneWidget);
  });

  testWidgets('se busca un ejército por nombre en vez de bajar a mano', (tester) async {
    await mostrar(tester, const PantallaDeFacciones());

    await tester.enterText(find.byKey(const ValueKey('buscar-faccion')), 'death');
    await tester.pumpAndSettle();
    expect(find.text('Death Guard'), findsOneWidget,
        reason: 'se enseña el nombre corto, no «Chaos - Death Guard»');
    expect(find.text('Orks'), findsNothing);
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
    expect(find.text('100'), findsWidgets, reason: 'los puntos, en la chapa de la cabecera');
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

  testWidgets('una palabra clave del arma se toca y se explica sin salir de la ficha',
      (tester) async {
    // Es la pregunta que más se hace en mitad de una partida: «¿qué hace [SUSTAINED HITS]?».
    final orks = dataset.factionNamed('Xenos - Orks');
    final wazdakka = orks.units.firstWhere((u) => u.name == 'Wazdakka Gutsmek');
    await mostrar(tester, PantallaDeUnidad(unidad: wazdakka, faccion: orks));

    final clave = find.byKey(const ValueKey('clave-SUSTAINED HITS 1'));
    await tester.dragUntilVisible(
        clave, find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(clave);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Sustained Hits'), findsOneWidget);
  });

  testWidgets('las habilidades CORE y FACTION salen en la ficha y se explican',
      (tester) async {
    final orks = dataset.factionNamed('Xenos - Orks');
    final wazdakka = orks.units.firstWhere((u) => u.name == 'Wazdakka Gutsmek');
    await mostrar(tester, PantallaDeUnidad(unidad: wazdakka, faccion: orks));

    await tester.dragUntilVisible(
        find.text('CORE:'), find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('CORE:'), findsOneWidget);
    expect(find.text('FACTION:'), findsOneWidget);
    expect(find.text('DEEP STRIKE'), findsOneWidget);
    expect(find.text('WAAAGH!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clave-Deep Strike')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('la salvación invulnerable sale con su nombre, no escondida en la línea',
      (tester) async {
    final orks = dataset.factionNamed('Xenos - Orks');
    final wazdakka = orks.units.firstWhere((u) => u.name == 'Wazdakka Gutsmek');
    await mostrar(tester, PantallaDeUnidad(unidad: wazdakka, faccion: orks));

    expect(find.text('SALVACIÓN INVULNERABLE'), findsOneWidget);
    expect(find.text('4+'), findsWidgets);
    // Y no como una casilla más llamada «InSv», que no la reconoce nadie.
    expect(find.text('INSV'), findsNothing);
  });

  testWidgets('se busca una unidad en las 36 facciones a la vez', (tester) async {
    await mostrar(tester, const PantallaDeBuscar());

    await tester.enterText(find.byKey(const ValueKey('buscar-unidad')), 'poxwalkers');
    await tester.pumpAndSettle();
    expect(find.text('Poxwalkers'), findsOneWidget);
    expect(find.text('DEATH GUARD'), findsOneWidget,
        reason: 'y dice de qué facción es, que es lo que no se sabía');
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
