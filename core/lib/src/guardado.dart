import 'dart:convert';

import 'dataset.dart';
import 'model.dart';
import 'roster.dart';

/// Guarda y recupera una lista.
///
/// Se guardan **las decisiones**, no el árbol resuelto: la facción, el tamaño de partida, los
/// detachments, los interruptores de contenido y qué unidades con qué opciones. Al recuperarla se
/// vuelve a montar contra el dataset de hoy.
///
/// Es a propósito. Guardar el árbol ya calculado congela los puntos del día en que se guardó, y
/// Games Workshop los cambia cada pocos meses: una lista de hace tres meses diría 1.985 puntos
/// cuando hoy son 2.010, y el jugador se presentaría a jugar con una lista ilegal creyéndola buena.
/// Al montarla de nuevo, o sale con los puntos correctos o sale avisando de lo que ya no cuadra.
abstract final class Guardado {
  /// Versión del formato. Si cambia la forma de lo guardado, esto permite no romper lo viejo.
  static const version = 1;

  static String aTexto(Roster roster) => jsonEncode(aJson(roster));

  static Map<String, dynamic> aJson(Roster roster) => {
        'version': version,
        'nombre': roster.name,
        'faccion': roster.faction.name,
        'tamano': roster.battleSize?.id,
        'limite': roster.pointsLimit,
        'detachments': [for (final d in roster.detachments) d.id],
        'interruptores': roster.shownOptions.toList(),
        'unidades': [for (final unit in roster.units) _seleccionAJson(unit)],
      };

  static Map<String, dynamic> _seleccionAJson(Selection selection) => {
        'id': selection.entryId,
        if (selection.groupId != null) 'grupo': selection.groupId,
        if (selection.count != 1) 'n': selection.count,
        if (selection.children.isNotEmpty)
          'hijos': [for (final child in selection.children) _seleccionAJson(child)],
      };

  /// Vuelve a montar la lista contra [dataset].
  ///
  /// Lanza [FormatException] si lo guardado no se puede leer. Que una unidad o una opción ya no
  /// exista **no** es un error: el dataset se refresca y a veces desaparece contenido, así que se
  /// monta lo que se pueda y se deja constancia en [Recuperada.perdidas].
  static Recuperada deTexto(Dataset dataset, String texto) =>
      deJson(dataset, jsonDecode(texto) as Map<String, dynamic>);

  static Recuperada deJson(Dataset dataset, Map<String, dynamic> json) {
    final guardadaCon = json['version'];
    if (guardadaCon is! int || guardadaCon > version) {
      throw FormatException('La lista se guardó con una versión más nueva de la app');
    }

    final faction = dataset.factions
        .where((f) => f.name == json['faccion'])
        .firstOrNull;
    if (faction == null) {
      throw FormatException('Ya no existe la facción ${json['faccion']}');
    }

    final roster = Roster(
      faction: faction,
      pointsLimit: (json['limite'] as num?)?.round() ?? 2000,
      name: json['nombre'] as String? ?? 'Lista sin nombre',
    );
    roster.battleSize =
        dataset.battleSizes.where((b) => b.id == json['tamano']).firstOrNull;
    roster.shownOptions
        .addAll((json['interruptores'] as List? ?? const []).cast<String>());

    final detachments = {
      for (final d in dataset.detachmentsOf(faction)) d.id: d,
      for (final d in dataset.detachmentsOf(faction, boardingActions: true)) d.id: d,
    };
    final perdidas = <String>[];
    for (final id in (json['detachments'] as List? ?? const [])) {
      final detachment = detachments[id];
      if (detachment == null) {
        perdidas.add('un detachment que ya no existe');
      } else {
        roster.detachments.add(detachment);
      }
    }

    // Después de los detachments: qué unidades se pueden montar depende de ellos.
    final disponibles = {for (final u in roster.availableUnits) u.id: u};
    for (final raw in (json['unidades'] as List? ?? const [])) {
      final guardada = raw as Map<String, dynamic>;
      final unit = disponibles[guardada['id']];
      if (unit == null) {
        perdidas.add('una unidad que esta lista ya no puede llevar');
        continue;
      }
      roster.add(_montar(roster, unit, guardada, perdidas));
    }
    return Recuperada(roster, perdidas);
  }

  /// Monta una unidad a partir de lo guardado, conciliándolo con lo que el dataset dice hoy.
  ///
  /// Se parte de la selección de partida —que ya trae los mínimos obligatorios, que pueden haber
  /// cambiado— y se ajusta a lo guardado. Lo que ya no se puede elegir se cae y se anota.
  static Selection _montar(
      Roster roster, UnitEntry unit, Map<String, dynamic> guardada, List<String> perdidas) {
    final selection = roster.selectionFor(unit);
    selection.count = (guardada['n'] as num?)?.round() ?? 1;
    _conciliar(roster, selection, guardada, perdidas);
    return selection;
  }

  static void _conciliar(Roster roster, Selection selection, Map<String, dynamic> guardada,
      List<String> perdidas) {
    final hijos = [
      for (final raw in (guardada['hijos'] as List? ?? const [])) raw as Map<String, dynamic>,
    ];
    final querido = {for (final hijo in hijos) hijo['id'] as String: hijo};

    selection.children.removeWhere((child) => !querido.containsKey(child.entryId));

    final opciones = roster.optionsFor(selection);
    for (final hijo in hijos) {
      final id = hijo['id'] as String;
      var puesto = selection.children.where((c) => c.entryId == id).firstOrNull;
      if (puesto == null) {
        final opcion = opciones.where((o) => o.entryId == id).firstOrNull;
        if (opcion == null) {
          perdidas.add('una opción que ya no se puede elegir');
          continue;
        }
        selection.addChild(opcion);
        puesto = opcion;
      }
      puesto.count = (hijo['n'] as num?)?.round() ?? 1;
      _conciliar(roster, puesto, hijo, perdidas);
    }
  }
}

/// Una lista recuperada, con lo que se haya quedado por el camino.
class Recuperada {
  Recuperada(this.roster, this.perdidas);

  final Roster roster;

  /// Lo que estaba guardado y hoy ya no se puede montar, para poder decírselo al jugador en vez de
  /// devolverle una lista distinta sin avisar.
  final List<String> perdidas;
}
