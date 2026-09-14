import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:warorgan_core/warorgan_core.dart';

/// De dónde salen los datos de la app.
///
/// Van empaquetados dentro: son 46 ficheros que se referencian entre ellos, así que se cargan
/// todos o no se resuelve nada. Es también lo que hace que la app funcione **sin conexión**, que
/// es de lo poco que no se negocia: en un torneo no hay cobertura.
abstract final class RepositorioDatos {
  static const _carpeta = 'assets/datos/';

  static Future<Dataset> cargar() async {
    final manifiesto = await AssetManifest.loadFromAssetBundle(rootBundle);
    final rutas = manifiesto
        .listAssets()
        .where((ruta) => ruta.startsWith(_carpeta) && ruta.endsWith('.json'))
        .toList()
      ..sort();
    if (rutas.isEmpty) {
      throw StateError(
        'No hay datos empaquetados. Genera el dataset en español con el pipeline y cópialo a '
        'app/assets/datos (ver README).',
      );
    }
    return Dataset.fromJson([for (final ruta in rutas) await rootBundle.loadString(ruta)]);
  }
}

/// Deja el dataset a mano de toda la app sin tener que ir pasándolo de pantalla en pantalla.
///
/// Va **por encima del MaterialApp**, no dentro: las pantallas que se abren con el Navigator se
/// construyen por encima de `home`, así que colgándolo de `home` no lo heredarían y habría que ir
/// pasándolo a mano en cada ruta.
class Datos extends InheritedWidget {
  const Datos({super.key, required this.dataset, required super.child});

  final Dataset dataset;

  static Dataset de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Datos>()!.dataset;

  @override
  bool updateShouldNotify(Datos anterior) => anterior.dataset != dataset;
}
