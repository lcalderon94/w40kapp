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
