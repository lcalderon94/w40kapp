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
