import 'model.dart';
import 'modifiers.dart';

/// Identificador del tipo de coste en puntos, declarado en el fichero del sistema de juego.
const pointsCostTypeId = '51b2-306e-1021-d207';

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
    required this.basePointsEach,
    this.count = 1,
    this.groupId,
    this.groupName,
    List<Selection>? children,
    List<Constraint>? constraints,
    List<Constraint>? groupConstraints,
    List<Modifier>? modifiers,
    List<String>? categoryIds,
  })  : pointsEach = basePointsEach,
        children = children ?? [],
        constraints = constraints ?? const [],
        groupConstraints = groupConstraints ?? const [],
        modifiers = modifiers ?? const [],
        categoryIds = categoryIds ?? const [] {
    for (final child in this.children) {
      child.parent = this;
    }
  }

  final String entryId;
  final String name;

  /// `unit`, `model` o `upgrade`.
  final String type;

  /// Puntos que declara el dataset para una instancia, antes de aplicar modifiers.
  final int basePointsEach;

  /// Puntos de una instancia ya con los modifiers aplicados. Lo recalcula la lista.
  int pointsEach;

  int count;

  /// Grupo de opciones del que sale esta selección, si sale de uno.
  ///
  /// Hace falta para validar y para los modifiers: los mínimos, máximos y condiciones suelen estar
  /// en el grupo («entre 10 y 20 Poxwalkers»), no en cada opción.
  final String? groupId;
  final String? groupName;

  final List<Selection> children;
  final List<Constraint> constraints;
  final List<Constraint> groupConstraints;
  final List<Modifier> modifiers;

  /// Categorías a las que pertenece. Las condiciones de los modifiers cuentan por categoría.
  final List<String> categoryIds;

  Selection? parent;

  void addChild(Selection child) {
    child.parent = this;
    children.add(child);
  }

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

  /// Coste de la lista, con los modifiers de coste ya aplicados.
  int get points {
    applyModifiers();
    return units.fold(0, (total, unit) => total + unit.points);
  }

  int get pointsRemaining => pointsLimit - points;

  void add(Selection unit) => units.add(unit);

  /// Recalcula el coste de cada selección aplicando los modifiers cuyas condiciones se cumplen.
  ///
  /// Sin esto una unidad de veinte Poxwalkers costaría lo mismo que una de diez: el dataset da 65
  /// como coste base y deja en un modifier que pase a 130 al superar las diez miniaturas.
  void applyModifiers() {
    skippedModifiers = 0;
    for (final selection in _all) {
      selection.pointsEach = selection.basePointsEach;
    }
    for (final selection in _all) {
      for (final modifier in selection.modifiers) {
        if (modifier.field != pointsCostTypeId) continue;
        if (!Modifier.numericTypes.contains(modifier.type)) continue;
        if (!modifier.isEvaluable) {
          skippedModifiers++;
          continue;
        }
        if (!modifier.appliesWhen((c) => _holds(c, selection))) continue;
        selection.pointsEach = modifier.applyTo(selection.pointsEach);
      }
    }
  }

  /// Modifiers de coste que se han dejado sin aplicar por no saber evaluar sus condiciones.
  ///
  /// Se expone en vez de esconderse: si no es cero, el precio puede quedarse corto y conviene
  /// saberlo. Lo llenan sobre todo los `localConditionGroups`.
  int skippedModifiers = 0;

  Iterable<Selection> get _all => units.expand((u) => u.descendantsAndSelf);

  bool _holds(Condition condition, Selection target) {
    // Solo se saben contar selecciones y puntos; otros tipos de coste aún no se siguen.
    if (condition.field != 'selections' && condition.field != pointsCostTypeId) return false;

    final scope = _scopeOf(condition, target).where((s) => _matches(condition.childId, s));
    final actual = condition.field == 'selections'
        ? scope.fold<int>(0, (total, s) => total + s.count)
        : scope.fold<int>(0, (total, s) => total + s.pointsEach * s.count);
    return condition.holdsFor(actual);
  }

  Iterable<Selection> _scopeOf(Condition condition, Selection target) {
    Iterable<Selection> expand(Iterable<Selection> roots) => condition.includeChildSelections
        ? roots.expand((s) => s.descendantsAndSelf)
        : roots;

    switch (condition.scope) {
      case 'self':
        return expand([target]);
      case 'parent':
        return expand(target.parent?.children ?? const []);
      case 'force':
      case 'roster':
        return expand(units);
      default:
        // El ámbito es el id de un grupo de opciones o de otra entrada.
        final inGroup = target.descendantsAndSelf.where((s) => s.groupId == condition.scope);
        if (inGroup.isNotEmpty) return expand(inGroup);
        final entry = _all.where((s) => s.entryId == condition.scope);
        return entry.isEmpty ? const [] : expand(entry.first.children);
    }
  }

  bool _matches(String childId, Selection selection) => switch (childId) {
        'any' => true,
        'model' || 'unit' || 'upgrade' => selection.type == childId,
        _ => selection.entryId == childId || selection.categoryIds.contains(childId),
      };

  /// Comprueba la legalidad de la lista.
  ///
  /// Cubre el límite de puntos y las restricciones de número de selecciones: los mínimos y máximos
  /// de cada opción, los de su grupo, y los que limitan cuántas veces puede repetirse una unidad en
  /// el ejército. No cubre todavía los modifiers que cambian restricciones en vez de costes, ni los
  /// límites por rol del destacamento.
  List<Violation> validate() {
    final violations = <Violation>[];
    final total = points;

    if (total > pointsLimit) {
      violations.add(Violation(null, 'La lista suma $total puntos y el límite es $pointsLimit'));
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
