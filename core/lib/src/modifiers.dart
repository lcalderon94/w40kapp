import 'dart:math' as math;

/// Identificador del tipo de coste en puntos, declarado en el fichero del sistema de juego.
const pointsCostTypeId = '51b2-306e-1021-d207';

/// Tipo de coste con el que el ejército paga sus mejoras. Cada mejora gasta una.
const enhancementsCostTypeId = 'f759-1bc4-cb3a-f0d2';

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
  ///
  /// Faltan `instanceOf` y `notInstanceOf`, que no cuentan nada: preguntan si la selección
  /// desciende de una entrada concreta, que es otra cosa y aún no se sigue.
  static const supportedTypes = {
    'atLeast', 'atMost', 'equalTo', 'notEqualTo', 'greaterThan', 'lessThan'
  };

  /// Nombres reservados de ámbito que esta capa no sabe recorrer.
  ///
  /// El esquema reserva unos cuantos nombres y deja que cualquier otro valor sea el id de un grupo
  /// o de una entrada. Los que no están aquí sí se recorren, así que hay que enumerar los que no:
  /// si no, un ámbito como `ancestor` se tomaría por un identificador, no encontraría nada, contaría
  /// cero y la condición saldría falsa sin que nadie se entere.
  static const unsupportedScopes = {
    'ancestor', 'root-entry', 'unit', 'model', 'model-or-unit', 'primary-catalogue',
  };

  /// Lo que esta capa sabe contar: selecciones y puntos. Los demás tipos de coste, no.
  static const supportedFields = {'selections', pointsCostTypeId};

  bool get isSupported =>
      supportedTypes.contains(type) &&
      supportedFields.contains(field) &&
      !unsupportedScopes.contains(scope);

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

/// Cuántas veces se repite un modifier, en función de lo que haya en la lista.
///
/// Es como el dataset escribe las proporciones: «una Bright Lance menos por cada Starcannon»,
/// «un no-Battleline de Khorne más por cada Battleline de Khorne». Sin esto el cambio se aplica
/// una sola vez y el límite sale mal en cuanto la unidad crece.
class Repeat {
  Repeat({
    required this.field,
    required this.scope,
    required this.childId,
    required this.value,
    required this.times,
    required this.roundUp,
    required this.includeChildSelections,
  });

  /// Qué se cuenta, igual que en una condición: `selections` o el id de un tipo de coste.
  final String field;
  final String scope;
  final String childId;

  /// Por cada cuántos. Contar 9 miniaturas con `value` 5 da una repetición, no dos.
  final num value;

  /// Cuántas veces se aplica el modifier por cada [value] que se cuenten.
  final int times;

  final bool roundUp;
  final bool includeChildSelections;

  factory Repeat.fromNode(Map<String, dynamic> node) => Repeat(
        field: node['field'] as String? ?? '',
        scope: node['scope'] as String? ?? '',
        childId: node['childId'] as String? ?? '',
        value: node['value'] as num? ?? 1,
        times: (node['repeats'] as num?)?.round() ?? 1,
        roundUp: node['roundUp'] as bool? ?? false,
        includeChildSelections: node['includeChildSelections'] as bool? ?? false,
      );

  /// Cuántas veces aplicar el modifier habiendo contado [actual].
  int timesFor(num actual) {
    if (value == 0) return 0;
    final groups = roundUp ? (actual / value).ceil() : (actual / value).floor();
    return groups * times;
  }

  bool get isSupported =>
      Condition.supportedFields.contains(field) && !Condition.unsupportedScopes.contains(scope);
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

  bool get isSupported => isSupportedWith((c) => c.isSupported);

  /// Igual, pero preguntando a [supports] por cada condición.
  ///
  /// Sirve para que quien evalúa pueda añadir lo que sepa contestar por su cuenta sin que esta
  /// clase tenga que saberlo: el roster, por ejemplo, sabe de qué tipo es la fuerza.
  bool isSupportedWith(bool Function(Condition) supports) =>
      !hasLocalGroups && conditions.every(supports) && groups.every((g) => g.isSupportedWith(supports));

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
    this.repeats = const [],
  });

  /// `set`, `increment`, `decrement`, `multiply`, y otros que esta capa aún no aplica.
  final String type;

  /// Qué cambia: el id de un tipo de coste, el id de una restricción, `name`, `category`…
  final String field;

  final Object? value;
  final List<Condition> conditions;
  final List<ConditionGroup> conditionGroups;

  /// Las proporciones que multiplican este cambio. Ver [Repeat].
  final List<Repeat> repeats;

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
        repeats: [
          for (final raw in (node['repeats'] as List? ?? const []))
            Repeat.fromNode(raw as Map<String, dynamic>),
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
          repeats: modifier.repeats,
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
  bool get isEvaluable => isEvaluableWith((c) => c.isSupported);

  /// Igual, pero preguntando a [supports] por cada condición. Ver [ConditionGroup.isSupportedWith].
  bool isEvaluableWith(bool Function(Condition) supports) =>
      conditions.every(supports) &&
      conditionGroups.every((g) => g.isSupportedWith(supports)) &&
      repeats.every((r) => r.isSupported);

  bool appliesWhen(bool Function(Condition) test) {
    if (!conditions.every(test)) return false;
    return conditionGroups.every((g) => g.evaluate(test));
  }

  /// Aplica el cambio sobre un valor numérico, [times] veces.
  ///
  /// Repetir importa en los incrementos y en las multiplicaciones; un `set` deja el mismo número
  /// se aplique una vez o siete, y con cero repeticiones no se aplica nada.
  int applyTo(int current, {int times = 1}) {
    final amount = value;
    if (amount is! num || times <= 0) return current;
    return switch (type) {
      'set' => amount.round(),
      'increment' => current + amount.round() * times,
      'decrement' => current - amount.round() * times,
      'multiply' => (current * math.pow(amount, times)).round(),
      _ => current,
    };
  }

  static const numericTypes = {'set', 'increment', 'decrement', 'multiply'};
}
