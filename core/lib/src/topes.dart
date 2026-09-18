/// «Por cada 5 miniaturas, 1 arma» — la regla leída de la frase impresa de la hoja.
///
/// BSData escribe esta misma regla de cuatro maneras distintas y ninguna es fiable por sí sola:
/// el Terminator la escribe bien —«max 1», y un modifier lo sube a 2 con diez miniaturas—, pero
/// el Plague Marine deja el techo en **2** —el de la escuadra llena— y mete la regla de verdad en
/// un modifier de tipo `error` que solo sirve para pintar un aviso en rojo. Con cinco Plague
/// Marines la app dejaba poner dos lanzaplagas y dos blight launchers: cuatro armas especiales en
/// una escuadra de cinco.
///
/// La frase, en cambio, lo dice igual en las 36 facciones y lo dice como lo dice el reglamento:
/// «For every 5 models in this unit, 1 Plague Marine's plague boltgun can be replaced with 1
/// blight launcher». De ahí sale el número, y de ahí sale para todas.
library;

/// Un «por cada [cada] miniaturas, hasta [cuantas]» y las armas a las que se aplica.
class TopePorMiniaturas {
  const TopePorMiniaturas({
    required this.cada,
    required this.cuantas,
    required this.armas,
    required this.frase,
  });

  /// El «5» de «por cada 5 miniaturas».
  final int cada;

  /// El «2» de «hasta 2 pueden»; uno, cuando la frase no dice número.
  final int cuantas;

  /// Las armas que nombra, normalizadas. Cuando hay varias, el tope es **el total entre todas**:
  /// «una de las siguientes» es una sola miniatura eligiendo, no una por arma.
  final List<String> armas;

  final String frase;

  /// El techo en una escuadra de [miniaturas].
  int enUnidadDe(int miniaturas) => (miniaturas ~/ cada) * cuantas;

  /// Si esta regla habla de esa opción. Se compara sobre el nombre de la miniatura —«Plague
  /// Marine w/ blight launcher»—, que es donde el dataset mete el arma.
  bool hablaDe(String nombreDeLaOpcion) {
    final limpio = _clave(nombreDeLaOpcion);
    return armas.any((a) => limpio.contains(a));
  }
}

final _porCada = RegExp(r'for every (\d+) models? in this unit\s*[:,]?\s*(.*)',
    caseSensitive: false, dotAll: true);
final _cuantas = RegExp(r'^\s*(?:up to\s+)?(\d+)\b', caseSensitive: false);
final _entra = RegExp(r'(?:replaced|equipped) with\s*(?:one of the following)?\s*:?\s*',
    caseSensitive: false);

/// Lo que entra, que es lo que va detrás del **último** «replaced with» del trozo.
///
/// Del último y no del primero: «1 model equipped with a bolt rifle can be equipped with 1
/// Astartes grenade launcher» lleva dos, y con el primero el arma salía siendo «a bolt rifle can
/// be equipped with…», que no casa con nada y dejaba la frase sin efecto.
String? _loQueEntra(String trozo) {
  final todas = _entra.allMatches(trozo).toList();
  if (todas.isEmpty) return null;
  return trozo.substring(todas.last.end);
}

String _clave(String s) => s
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Lee las reglas de tope de las frases impresas de una unidad.
List<TopePorMiniaturas> topesDe(Iterable<String> notas) {
  final salida = <TopePorMiniaturas>[];
  for (final nota in notas) {
    for (final clausula in nota.split('|')) {
      final m = _porCada.firstMatch(clausula);
      if (m == null) continue;
      final cada = int.parse(m.group(1)!);
      if (cada <= 0) continue;

      // Una frase puede llevar varias reglas dentro —el Blightlord encadena cuatro con «;»— y a
      // la vez el «;» separa las armas de una lista. Se distinguen por el verbo: el trozo que
      // dice «replaced with» abre regla nueva, y el que no, son más armas de la anterior.
      final trozos = m.group(2)!.split(';');
      var actual = <String>[];
      var pendiente = <String>[];
      void cierra() {
        if (pendiente.isEmpty || actual.isEmpty) return;
        final armas = _armasDe(actual);
        if (armas.isNotEmpty) {
          salida.add(TopePorMiniaturas(
            cada: cada,
            cuantas: _cuantasDe(pendiente.first),
            armas: armas,
            frase: pendiente.join('; ').trim(),
          ));
        }
        actual = [];
        pendiente = [];
      }

      for (final trozo in trozos) {
        final entra = _loQueEntra(trozo);
        if (entra != null) {
          cierra();
          pendiente = [trozo];
          actual = [entra];
        } else if (pendiente.isNotEmpty) {
          pendiente.add(trozo);
          actual.add(trozo);
        }
      }
      cierra();
    }
  }
  return salida;
}

/// Los nombres de arma de los trozos, ya normalizados.
///
/// «1 cyclone missile launcher and 1 storm bolter» son dos nombres, no uno: la miniatura del
/// dataset se llama «Terminator w/ Cyclone missile launcher» y con la frase entera no casaría.
List<String> _armasDe(List<String> trozos) {
  final armas = <String>[];
  for (final trozo in trozos) {
    for (final pieza in trozo.split(RegExp(r'\band\b|\bor\b', caseSensitive: false))) {
      final limpia = _clave(pieza.replaceAll(RegExp(r'^\s*\d+\s*'), ''));
      if (limpia.length < 5) continue;
      // Las coletillas de la hoja no son armas.
      if (limpia.startsWith('the profile for this')) continue;
      if (limpia.startsWith('maximum one per')) continue;
      if (limpia.startsWith('this model')) continue;
      if (limpia.startsWith('that model')) continue;
      if (limpia.startsWith('duplicates are not')) continue;
      armas.add(limpia);
    }
  }
  return armas;
}

int _cuantasDe(String trozo) {
  final m = _cuantas.firstMatch(trozo);
  if (m == null) return 1;
  final n = int.parse(m.group(1)!);
  return n <= 0 ? 1 : n;
}
