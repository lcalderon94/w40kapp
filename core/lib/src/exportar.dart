import 'modifiers.dart';
import 'roster.dart';

/// Pasa una lista a texto plano, para pegarla en un chat o enseñarla en la mesa.
///
/// El formato imita al que ya circula entre jugadores —cabecera, unidades con sus puntos, equipo
/// indentado— porque la gracia es que el de enfrente lo lea de un vistazo, no que sea bonito.
/// Sin negritas ni caracteres raros: acaba en WhatsApp tanto como en un papel.
abstract final class Exportar {
  static String aTexto(Roster roster) {
    final lineas = <String>[];
    final tamano = roster.battleSize;

    lineas.add(roster.name);
    lineas.add([
      roster.faction.name.split(' - ').last,
      if (tamano != null) _tamanoCorto(tamano.name),
      '${roster.points}/${roster.pointsLimit} pts',
    ].join(' · '));
    for (final detachment in roster.detachments) {
      lineas.add(detachment.ruleName == null
          ? detachment.name
          : '${detachment.name} (${detachment.ruleName})');
    }

    final mejoras = roster.units
        .fold(0, (total, unidad) => total + unidad.costOf(enhancementsCostTypeId));
    if (mejoras > 0) lineas.add('$mejoras ${mejoras == 1 ? "mejora" : "mejoras"}');

    // Agrupadas por rol, como en la hoja de ejército.
    final porRol = <String, List<Selection>>{};
    for (final unidad in roster.units) {
      porRol.putIfAbsent(_rolDe(roster, unidad), () => []).add(unidad);
    }
    for (final rol in porRol.keys.toList()..sort()) {
      lineas.add('');
      lineas.add(rol.toUpperCase());
      for (final unidad in porRol[rol]!) {
        lineas.add('  ${_nombreCon(unidad)} — ${unidad.points} pts');
        for (final linea in _equipoDe(unidad)) {
          lineas.add('    $linea');
        }
      }
    }

    final incumplimientos = roster.validate();
    if (incumplimientos.isNotEmpty) {
      lineas.add('');
      lineas.add('AVISOS');
      for (final incumplimiento in incumplimientos) {
        lineas.add('  - $incumplimiento');
      }
    }
    return lineas.join('\n');
  }

  static String _nombreCon(Selection unidad) =>
      unidad.count > 1 ? '${unidad.count}× ${unidad.name}' : unidad.name;

  /// El equipo elegido, sin repetir y sin lo que no aporta nada al que lee.
  static List<String> _equipoDe(Selection unidad) {
    final lineas = <String>[];
    for (final hijo in unidad.children) {
      if (hijo.name.isEmpty) continue;
      final puntos = hijo.points > 0 ? ' (${hijo.points} pts)' : '';
      lineas.add('${_nombreCon(hijo)}$puntos');
      for (final nieto in _equipoDe(hijo)) {
        lineas.add('  $nieto');
      }
    }
    return lineas;
  }

  /// El rol con el que se agrupa: la categoría **principal**, no la primera que aparezca.
  ///
  /// Un Daemon Prince es Character, Monster, Fly y Chaos a la vez; en la hoja de ejército va bajo
  /// Character porque es la que el dataset marca como principal.
  static String _rolDe(Roster roster, Selection unidad) {
    final nombre = roster.faction.dataset.node(unidad.primaryCategoryId ?? '')?['name'];
    if (nombre is String && nombre.isNotEmpty) return nombre;
    for (final id in roster.categoriesOf(unidad)) {
      final otra = roster.faction.dataset.node(id)?['name'];
      if (otra is String && otra.isNotEmpty && !otra.startsWith('Faction:')) return otra;
    }
    return 'Unidades';
  }

  static String _tamanoCorto(String nombre) {
    final sinNumero = nombre.replaceFirst(RegExp(r'^\d+\.\s*'), '');
    final parentesis = sinNumero.indexOf(' (');
    return parentesis == -1 ? sinNumero : sinNumero.substring(0, parentesis);
  }
}
