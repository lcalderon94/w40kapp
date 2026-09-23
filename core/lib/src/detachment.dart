/// Un detachment de una facción: la plantilla que define cómo se construye el ejército.
///
/// El jugador elige uno, y esa elección decide qué Enhancements tiene disponibles y qué regla
/// especial gana su ejército.
class Detachment {
  Detachment({
    required this.id,
    required this.name,
    required this.ruleName,
    required this.rule,
    required this.points,
    required this.detachmentPoints,
    this.disposiciones = const [],
  });

  final String id;
  final String name;

  final String? ruleName;

  /// El texto de la regla del detachment, ya traducido.
  final String? rule;

  /// Coste en puntos, si lo tiene. La mayoría son gratuitos.
  final int points;

  /// Lo que gasta del presupuesto de Detachment Points del ejército.
  ///
  /// Es como 11ª gradúa los detachments: los de 2 y 3 son los de una partida normal, los de 1 son
  /// pequeños. El presupuesto lo pone el tamaño de partida, así que en Onslaught caben dos.
  final int detachmentPoints;

  /// La disposición de fuerza del detachment: Take and Hold, Purge the Foe, Disruption, Priority
  /// Assets o Reconnaissance. Es lo que decide qué misiones juega el ejército, y lo que el
  /// jugador mira al elegir; el nombre de la regla del detachment va dentro, al desplegarlo.
  final List<String> disposiciones;
}

/// Una mejora que se asigna a un personaje del ejército.
///
/// Cada detachment habilita las suyas, normalmente cuatro.
class Enhancement {
  Enhancement({
    required this.id,
    required this.name,
    required this.points,
    required this.description,
  });

  final String id;
  final String name;
  final int points;

  /// El texto de la mejora, ya traducido.
  final String? description;
}
