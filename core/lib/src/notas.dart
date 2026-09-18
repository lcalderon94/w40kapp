import 'dart:convert';

import 'model.dart';

/// Las opciones de equipo **dichas como las dice la hoja impresa**.
///
/// «For every 5 models in this unit, 1 Terminator's storm bolter can be replaced with one of the
/// following: 1 assault cannon ; 1 heavy flamer ; 1 cyclone missile launcher and 1 storm bolter.»
///
/// BSData no trae esa frase en ninguna parte: escribe la misma regla como un techo que sube al
/// crecer la escuadra, que es exacto pero no se lee. Las dos cosas hacen falta y hacen cosas
/// distintas: **el número lo pone el dataset** —es el que cuenta, valida y cobra— y **la frase la
/// pone esto**, para saber qué se está eligiendo.
///
/// Por eso esto no decide nada. Es texto, y texto de las index cards de 10ª: el 84 % de las armas
/// que nombra siguen existiendo en 11ª, y el resto ha cambiado. Dejar que decidiera haría listas
/// ilegales; enseñándolo al lado del número vigente, lo que se ve es la regla y lo que se cuenta
/// es el dato de hoy.
class NotasDeEquipo {
  const NotasDeEquipo(this._porUnidad);

  const NotasDeEquipo.vacia() : _porUnidad = const {};

  final Map<String, List<String>> _porUnidad;

  bool get isEmpty => _porUnidad.isEmpty;
  int get length => _porUnidad.length;

  factory NotasDeEquipo.desdeJson(String texto) {
    final crudo = jsonDecode(texto) as Map<String, dynamic>;
    return NotasDeEquipo({
      for (final entrada in crudo.entries)
        entrada.key: [
          for (final o in ((entrada.value as Map<String, dynamic>)['opciones'] as List? ??
              const []))
            o as String,
        ],
    });
  }

  /// Lo que la hoja dice que se puede cambiar en esta unidad.
  ///
  /// El nombre no siempre coincide letra a letra: 11ª le quitó el «Primaris» a media docena de
  /// personajes y los capítulos ponen el suyo delante —«Black Templars Gladiator Lancer» es el
  /// «Gladiator Lancer» de siempre—. Se prueba el nombre tal cual, luego sin esos adornos, y por
  /// último dejando que uno contenga al otro, que es lo que recupera los compuestos.
  List<String> of(UnitEntry unit) {
    final buscado = clave(unit.name);
    if (buscado.isEmpty) return const [];

    final directo = _porUnidad[buscado] ?? _porUnidad[_sinAdornos(buscado)];
    if (directo != null) return directo;

    // El que contenga al otro y sea lo bastante largo para no casar por casualidad: «captain»
    // casaría con media docena de hojas, «gladiatorlancer» solo con la suya.
    if (buscado.length < 8) return const [];
    String? mejor;
    for (final clave in _porUnidad.keys) {
      final limpia = _sinAdornos(clave);
      if (limpia.length < 8) continue;
      if (!limpia.endsWith(buscado) && !buscado.endsWith(limpia)) continue;
      if (mejor == null || limpia.length > mejor.length) mejor = clave;
    }
    return mejor == null ? const [] : _porUnidad[mejor]!;
  }

  /// Sin «Primaris» ni el nombre del capítulo o de la legión delante.
  static String _sinAdornos(String clave) {
    var salida = clave;
    for (final prefijo in _prefijos) {
      if (salida.length > prefijo.length + 4 && salida.startsWith(prefijo)) {
        salida = salida.substring(prefijo.length);
      }
    }
    return salida;
  }

  /// Los nombres que las facciones se ponen delante de una hoja que comparten.
  static const _prefijos = [
    'primaris',
    'deathguard',
    'blacktemplars',
    'bloodangels',
    'darkangels',
    'spacewolves',
    'ultramarines',
    'whitescars',
    'ironhands',
    'ravenguard',
    'salamanders',
    'imperialfists',
    'deathwatch',
    'greyknights',
    'thousandsons',
    'worldeaters',
    'emperorschildren',
    'chaos',
  ];

  /// La clave con la que se busca una unidad. La misma que escribe `tool/notas-de-equipo.dart`.
  static String clave(String nombre) {
    const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    return nombre
        .toLowerCase()
        .split('')
        .map((c) => tildes[c] ?? c)
        .join()
        .replaceAll(RegExp(r'\[(legends|crucible)\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
