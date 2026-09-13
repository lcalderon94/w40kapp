/// Una condición para que un modifier se aplique.
///
/// Cuenta algo dentro de un ámbito y lo compara con un valor: «cuántas miniaturas hay en este
/// grupo», «cuántas unidades de este tipo hay en el ejército».
class Condition {
  Condition({
    required this.type,
    required this.field,
    required this.scope,
    required this.childId,
    required this.value,
    required this.includeChildSelections,
  });

  /// `atLeast`, `atMost`, `equalTo`, `notEqualTo`, `greaterThan`, `lessThan`.
  final String type;

  /// Tipos de comparación que esta capa sabe evaluar.
  static const supportedTypes = {
    'atLeast', 'atMost', 'equalTo', 'notEqualTo', 'greaterThan', 'lessThan'
  };

  bool get isSupported => supportedTypes.contains(type);

  /// `selections` para contar selecciones, o el id de un tipo de coste para sumarlo.
  final String field;

  /// `self`, `parent`, `force`, `roster`, o el id de un grupo o entrada concretos.
  final String scope;

  /// Qué se cuenta: `any`, un tipo (`model`, `unit`, `upgrade`), o el id de una entrada o categoría.
  final String childId;

  final num value;
  final bool includeChildSelections;

  factory Condition.fromNode(Map<String, dynamic> node) => Condition(
        type: node['type'] as String? ?? '',
        field: node['field'] as String? ?? '',
        scope: node['scope'] as String? ?? '',
        childId: node['childId'] as String? ?? '',
        value: node['value'] as num? ?? 0,
        includeChildSelections: node['includeChildSelections'] as bool? ?? false,
      );

  bool holdsFor(num actual) => switch (type) {
        'atLeast' => actual >= value,
        'atMost' => actual <= value,
        'equalTo' => actual == value,
        'notEqualTo' => actual != value,
        'greaterThan' => actual > value,
        'lessThan' => actual < value,
        _ => false,
      };
}

/// Un conjunto de condiciones que se cumplen todas (`and`) o alguna (`or`). Puede anidarse.
class ConditionGroup {
  ConditionGroup({
    required this.type,
    required this.conditions,
    required this.groups,
    this.hasLocalGroups = false,
  });

  final String type; // and | or
  final List<Condition> conditions;
  final List<ConditionGroup> groups;

  /// El grupo contiene `localConditionGroups`, que esta capa todavía no sabe evaluar.
  ///
  /// Cuentan cuántas selecciones hermanas cumplen algo («si es el segundo Foetid Bloat-drone del
  /// destacamento, +10 puntos») usando comparaciones propias como `before` e `instanceOf`. Mientras
  /// no se implementen, un grupo así se da por no evaluable y su modifier no se aplica: es
  /// preferible dejar el precio base a inventarse uno.
  final bool hasLocalGroups;

  bool get isSupported =>
      !hasLocalGroups &&
      conditions.every((c) => c.isSupported) &&
      groups.every((g) => g.isSupported);

  factory ConditionGroup.fromNode(Map<String, dynamic> node) => ConditionGroup(
        type: node['type'] as String? ?? 'and',
        hasLocalGroups: (node['localConditionGroups'] as List? ?? const []).isNotEmpty,
        conditions: [
          for (final raw in (node['conditions'] as List? ?? const []))
            Condition.fromNode(raw as Map<String, dynamic>),
        ],
        groups: [
          for (final raw in (node['conditionGroups'] as List? ?? const []))
            ConditionGroup.fromNode(raw as Map<String, dynamic>),
        ],
      );

  /// Todas las condiciones del grupo y de los que anida.
  Iterable<Condition> get allConditions sync* {
    yield* conditions;
    for (final group in groups) {
      yield* group.allConditions;
    }
  }

  bool evaluate(bool Function(Condition) test) {
    final results = [
      ...conditions.map(test),
      ...groups.map((g) => g.evaluate(test)),
    ];
    if (results.isEmpty) return true;
    return type == 'or' ? results.any((r) => r) : results.every((r) => r);
  }
}

/// Un cambio condicional sobre una entrada: su coste, una de sus restricciones, su nombre.
///
/// Es lo que hace que una unidad de veinte Poxwalkers no cueste lo mismo que una de diez: el coste
/// base es 65 y un modifier lo pone en 130 cuando el grupo pasa de diez miniaturas.
class Modifier {
  Modifier({
    required this.type,
    required this.field,
    required this.value,
    required this.conditions,
    required this.conditionGroups,
  });

  /// `set`, `increment`, `decrement`, `multiply`, y otros que esta capa aún no aplica.
  final String type;

  /// Qué cambia: el id de un tipo de coste, el id de una restricción, `name`, `category`…
  final String field;

  final Object? value;
  final List<Condition> conditions;
  final List<ConditionGroup> conditionGroups;

  factory Modifier.fromNode(Map<String, dynamic> node) => Modifier(
        type: node['type'] as String? ?? '',
        field: node['field'] as String? ?? '',
        value: node['value'],
        conditions: [
          for (final raw in (node['conditions'] as List? ?? const []))
            Condition.fromNode(raw as Map<String, dynamic>),
        ],
        conditionGroups: [
          for (final raw in (node['conditionGroups'] as List? ?? const []))
            ConditionGroup.fromNode(raw as Map<String, dynamic>),
        ],
      );

  /// Los modifiers de una entrada, incluidos los que vienen dentro de un `modifierGroup`.
  ///
  /// Un grupo puede tener sus propias condiciones, que valen para todos los modifiers que
  /// contiene; se copian a cada uno para poder evaluarlos por separado.
  static List<Modifier> allOf(Map<String, dynamic> entry) {
    final modifiers = <Modifier>[];
    for (final raw in (entry['modifiers'] as List? ?? const [])) {
      modifiers.add(Modifier.fromNode(raw as Map<String, dynamic>));
    }
    for (final raw in (entry['modifierGroups'] as List? ?? const [])) {
      final group = raw as Map<String, dynamic>;
      final gate = ConditionGroup.fromNode(group);
      for (final inner in (group['modifiers'] as List? ?? const [])) {
        final modifier = Modifier.fromNode(inner as Map<String, dynamic>);
        modifiers.add(Modifier(
          type: modifier.type,
          field: modifier.field,
          value: modifier.value,
          conditions: modifier.conditions,
          conditionGroups: [...modifier.conditionGroups, gate],
        ));
      }
    }
    return modifiers;
  }

  /// Todas las condiciones del modifier, estén sueltas o dentro de un grupo.
  Iterable<Condition> get allConditions sync* {
    yield* conditions;
    for (final group in conditionGroups) {
      yield* group.allConditions;
    }
  }

  /// Si el motor entiende todas sus condiciones. Cuando no, el modifier se deja sin aplicar.
  bool get isEvaluable =>
      conditions.every((c) => c.isSupported) && conditionGroups.every((g) => g.isSupported);

  bool appliesWhen(bool Function(Condition) test) {
    if (!conditions.every(test)) return false;
    return conditionGroups.every((g) => g.evaluate(test));
  }

  /// Aplica el cambio sobre un valor numérico. Devuelve el valor original si no sabe hacerlo.
  int applyTo(int current) {
    final amount = value;
    if (amount is! num) return current;
    return switch (type) {
      'set' => amount.round(),
      'increment' => current + amount.round(),
      'decrement' => current - amount.round(),
      'multiply' => (current * amount).round(),
      _ => current,
    };
  }

  static const numericTypes = {'set', 'increment', 'decrement', 'multiply'};
}
