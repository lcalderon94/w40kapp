import 'model.dart';

/// Una selección dentro de una lista: una unidad, una de sus miniaturas o una opción de equipo.
///
/// El coste de una lista es la suma de este árbol, no el precio de la unidad. Los Poxwalkers
/// cuestan 65 en la unidad y 0 en cada una de sus diez miniaturas; el Myphitic Blight-hauler
/// cuesta 0 en la unidad y 95 en la suya.
class Selection {
  Selection({
    required this.entryId,
    required this.name,
    required this.type,
    required this.pointsEach,
    this.count = 1,
    this.groupId,
    this.groupName,
    List<Selection>? children,
    List<Constraint>? constraints,
    List<Constraint>? groupConstraints,
  })  : children = children ?? [],
        constraints = constraints ?? const [],
        groupConstraints = groupConstraints ?? const [];

  final String entryId;
  final String name;

  /// `unit`, `model` o `upgrade`.
  final String type;

  /// Puntos de una sola instancia.
  final int pointsEach;

  int count;

  /// Grupo de opciones del que sale esta selección, si sale de uno.
  ///
  /// Hace falta para validar: los mínimos y máximos suelen estar en el grupo («entre 10 y 20
  /// Poxwalkers»), no en cada opción, así que se comprueban sumando los hermanos del mismo grupo.
  final String? groupId;
  final String? groupName;

  final List<Selection> children;
  final List<Constraint> constraints;
  final List<Constraint> groupConstraints;

  /// Puntos de esta selección y de todo lo que cuelga de ella.
  int get points =>
      pointsEach * count + children.fold(0, (total, child) => total + child.points);

  /// Esta selección y toda su descendencia.
  Iterable<Selection> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }
}

/// Un incumplimiento de las reglas de construcción de listas.
class Violation {
  Violation(this.selection, this.message);

  /// La selección afectada, o `null` si el problema es de la lista entera.
  final Selection? selection;
  final String message;

  @override
  String toString() => selection == null ? message : '${selection!.name}: $message';
}

/// Una lista de ejército en construcción.
class Roster {
  Roster({required this.faction, required this.pointsLimit, this.name = 'Lista sin nombre'});

  final Faction faction;
  final int pointsLimit;
  String name;
  final List<Selection> units = [];

  int get points => units.fold(0, (total, unit) => total + unit.points);
  int get pointsRemaining => pointsLimit - points;

  void add(Selection unit) => units.add(unit);

  /// Comprueba la legalidad de la lista.
  ///
  /// Cubre el límite de puntos y las restricciones de número de selecciones: los mínimos y máximos
  /// de cada opción, los de su grupo, y los que limitan cuántas veces puede repetirse una unidad en
  /// el ejército. No cubre todavía los `modifiers`, que cambian costes y restricciones según el
  /// contexto, ni los límites por rol del destacamento.
  List<Violation> validate() {
    final violations = <Violation>[];

    if (points > pointsLimit) {
      violations.add(Violation(null, 'La lista suma $points puntos y el límite es $pointsLimit'));
    }

    for (final unit in units) {
      _validateSelection(unit, violations);
    }
    _validateArmyWide(violations);
    return violations;
  }

  void _validateSelection(Selection selection, List<Violation> violations) {
    for (final child in selection.children) {
      for (final constraint in child.constraints) {
        if (constraint.field != 'selections') continue;
        if (constraint.scope != 'parent' && constraint.scope != 'self') continue;
        _check(child, child.count, constraint, violations, child.name);
      }
    }

    // Las restricciones del grupo se cumplen entre todos los hermanos que salen de él.
    final byGroup = <String, List<Selection>>{};
    for (final child in selection.children) {
      if (child.groupId != null) {
        byGroup.putIfAbsent(child.groupId!, () => []).add(child);
      }
    }
    for (final siblings in byGroup.values) {
      final total = siblings.fold(0, (sum, s) => sum + s.count);
      for (final constraint in siblings.first.groupConstraints) {
        if (constraint.field != 'selections') continue;
        _check(siblings.first, total, constraint, violations,
            siblings.first.groupName ?? siblings.first.name);
      }
    }

    for (final child in selection.children) {
      _validateSelection(child, violations);
    }
  }

  /// Restricciones que se cuentan sobre el ejército entero, como «máximo 3 de esta unidad».
  void _validateArmyWide(List<Violation> violations) {
    final counts = <String, int>{};
    for (final unit in units) {
      counts.update(unit.entryId, (n) => n + unit.count, ifAbsent: () => unit.count);
    }
    for (final unit in units) {
      for (final constraint in unit.constraints) {
        if (constraint.field != 'selections') continue;
        if (constraint.scope != 'force' && constraint.scope != 'roster') continue;
        _check(unit, counts[unit.entryId] ?? 0, constraint, violations, unit.name);
      }
    }
  }

  void _check(Selection selection, int actual, Constraint constraint, List<Violation> violations,
      String subject) {
    final broken = constraint.isMax ? actual > constraint.value : actual < constraint.value;
    if (!broken) return;
    final message = constraint.message ??
        (constraint.isMax
            ? 'como máximo ${constraint.value}, hay $actual'
            : 'mínimo ${constraint.value}, hay $actual');
    violations.add(Violation(selection, '$subject: $message'));
  }
}
