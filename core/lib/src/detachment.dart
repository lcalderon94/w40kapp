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
  });

  final String id;
  final String name;

  final String? ruleName;

  /// El texto de la regla del detachment, ya traducido.
  final String? rule;

  /// Coste en puntos, si lo tiene. La mayoría son gratuitos.
  final int points;
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
