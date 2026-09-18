import 'package:shared_preferences/shared_preferences.dart';
import 'package:warorgan_core/warorgan_core.dart';

/// Dónde viven las listas del jugador entre una sesión y otra.
///
/// Guarda **las decisiones**, no el árbol resuelto: al abrir la app la lista se vuelve a montar
/// contra el dataset. Es a propósito —Games Workshop cambia los puntos cada pocos meses— y es lo
/// que evita presentarse a jugar con una lista que dice 1.985 cuando hoy son 2.010.
class Almacen {
  Almacen(this._preferencias);

  static const _clave = 'listas';

  final SharedPreferences _preferencias;

  static Future<Almacen> abrir() async => Almacen(await SharedPreferences.getInstance());

  /// Lo guardado, tal cual. Cada entrada es una lista serializada.
  List<String> get guardadas => _preferencias.getStringList(_clave) ?? const [];

  Future<void> escribir(List<String> listas) =>
      _preferencias.setStringList(_clave, listas);

  /// Monta lo guardado contra el dataset.
  ///
  /// Lo que no se pueda leer no tumba el resto: una lista rota es molesta, perderlas todas es
  /// grave. Se devuelven las que se hayan podido montar y el recuento de las que no.
  ({List<Recuperada> listas, int ilegibles}) recuperar(Dataset dataset) {
    final listas = <Recuperada>[];
    var ilegibles = 0;
    for (final texto in guardadas) {
      try {
        listas.add(Guardado.deTexto(dataset, texto));
      } catch (_) {
        ilegibles++;
      }
    }
    return (listas: listas, ilegibles: ilegibles);
  }
}

/// El historial de búsquedas de unidades, para volver a lo último sin escribirlo otra vez.
///
/// Guarda el identificador de la unidad y el de su facción, no el nombre: los nombres cambian de
/// una revisión del dataset a otra y el historial se quedaría apuntando a nada.
class Historial {
  Historial(this._preferencias);

  static const _clave = 'historial';
  static const _maximo = 40;

  final SharedPreferences _preferencias;

  static Future<Historial> abrir() async => Historial(await SharedPreferences.getInstance());

  List<({String faccion, String unidad})> get entradas => [
        for (final linea in _preferencias.getStringList(_clave) ?? const <String>[])
          if (linea.contains('|'))
            (faccion: linea.split('|').first, unidad: linea.split('|').last),
      ];

  /// Apunta una consulta. Lo más reciente primero, y sin repetir.
  Future<void> apuntar({required String faccion, required String unidad}) async {
    final lineas = (_preferencias.getStringList(_clave) ?? const <String>[]).toList()
      ..removeWhere((l) => l == '$faccion|$unidad')
      ..insert(0, '$faccion|$unidad');
    await _preferencias.setStringList(_clave, lineas.take(_maximo).toList());
  }

  Future<void> vaciar() => _preferencias.remove(_clave);
}
