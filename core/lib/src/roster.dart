import 'detachment.dart';
import 'model.dart';
import 'modifiers.dart';

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
    List<Modifier>? groupModifiers,
    List<String>? categoryIds,
  })  : pointsEach = basePointsEach,
        children = children ?? [],
        constraints = constraints ?? const [],
        groupConstraints = groupConstraints ?? const [],
        modifiers = modifiers ?? const [],
        groupModifiers = groupModifiers ?? const [],
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

  /// Modifiers de coste de esta selección que no se han podido evaluar.
  ///
  /// Mayor que cero significa que su precio puede quedarse corto, y la interfaz debería avisar en
  /// esa unidad en concreto en vez de poner en duda la lista entera.
  int unresolvedCostModifiers = 0;

  /// Restricciones de esta selección cuyo límite efectivo no se ha podido calcular.
  ///
  /// Mayor que cero significa que esa restricción no se ha comprobado: el dataset la cambia con un
  /// modifier que el motor no sabe evaluar, y comprobar el número declarado daría un aviso falso.
  int uncheckedConstraints = 0;

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

  /// Los modifiers del grupo de opciones, que son los que cambian sus restricciones.
  final List<Modifier> groupModifiers;

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

  /// El detachment elegido. Un ejército necesita uno, y es lo que decide sus reglas.
  Detachment? detachment;

  /// El tamaño de la partida.
  ///
  /// No es lo mismo que [pointsLimit], aunque cada tamaño traiga el suyo: **cambia las reglas de
  /// construcción**. Muchas unidades se pueden repetir tres veces en Strike Force y solo dos en
  /// Incursion, y eso lo decide un modifier sobre la restricción que mira cuál se ha elegido. Sin
  /// tamaño esos modifiers no se pueden evaluar y esos límites se quedan sin comprobar.
  BattleSize? battleSize;

  /// El tipo de lista. Por defecto una partida normal, que es lo que asume el constructor.
  ///
  /// Hay reglas que solo valen en algunos: el máximo de Poxwalkers se dobla en Crusade, y las
  /// unidades de Boarding Actions se recortan a la mitad.
  Force? force;

  Force get _force => force ?? faction.dataset.standardForce;

  /// Coste de la lista, con los modifiers de coste ya aplicados.
  int get points {
    applyModifiers();
    return units.fold(detachment?.points ?? 0, (total, unit) => total + unit.points);
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
      selection.unresolvedCostModifiers = 0;
    }
    for (final selection in _all) {
      for (final modifier in selection.modifiers) {
        if (modifier.field != pointsCostTypeId) continue;
        if (!Modifier.numericTypes.contains(modifier.type)) continue;
        if (!_canEvaluate(modifier)) {
          skippedModifiers++;
          selection.unresolvedCostModifiers++;
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
  /// saberlo. Los llenan los `localConditionGroups`, una construcción que el dataset usa pero que
  /// no aparece en ningún esquema publicado de BattleScribe, ni en el 2.03 que el propio dataset
  /// declara ni en vNext; su condición interna `before` tampoco está en la lista oficial de tipos.
  /// Sin especificación no se implementan: un precio mal calculado parece correcto.
  ///
  /// En la práctica solo afectan a listas con **copias repetidas de la misma unidad**: todas esas
  /// condiciones cuentan instancias anteriores, así que con una sola copia no pueden dispararse y
  /// el precio es exacto.
  int skippedModifiers = 0;

  /// Las selecciones cuyo precio puede quedarse corto, para poder señalarlas en la interfaz.
  Iterable<Selection> get selectionsWithUnresolvedCost =>
      _all.where((s) => s.unresolvedCostModifiers > 0);

  Iterable<Selection> get _all => [...units.expand((u) => u.descendantsAndSelf), ..._configuration];

  /// Las selecciones de configuración de la lista: el tamaño de partida y el detachment.
  ///
  /// En el dataset son selecciones como cualquier otra, solo que sin puntos, y las condiciones de
  /// los modifiers preguntan por ellas: «máximo 2 si la partida es Incursion», «esta unidad solo
  /// con tal detachment». Si no están en el ámbito, esas condiciones cuentan cero y salen falsas.
  List<Selection> get _configuration {
    final key = '\${battleSize?.id}|\${detachment?.id}';
    if (_configurationKey == key) return _configurationCache;
    _configurationKey = key;
    return _configurationCache = [
      for (final id in [battleSize?.id, detachment?.id])
        if (id != null)
          Selection(entryId: id, name: '', type: 'upgrade', basePointsEach: 0),
    ];
  }

  String? _configurationKey;
  List<Selection> _configurationCache = const [];

  /// Si el motor puede evaluar este modifier. Amplía [Modifier.isEvaluable] con lo que sabe la
  /// lista y no puede saber una condición suelta: de qué tipo es la fuerza.
  bool _canEvaluate(Modifier modifier) => modifier.isEvaluableWith(
      (c) => (c.isSupported || _isForceTypeQuestion(c)) && !_asksForUnknownBattleSize(c));

  /// Si la condición pregunta por el tamaño de la partida y la lista todavía no tiene ninguno.
  ///
  /// Sin tamaño no se puede contestar, y contestar «no» sería peor que no contestar: dejaría el
  /// límite de Strike Force puesto en una lista que a lo mejor es de Incursion.
  bool _asksForUnknownBattleSize(Condition condition) =>
      battleSize == null && faction.dataset.battleSizes.any((b) => b.id == condition.childId);

  /// Si la condición pregunta de qué tipo es la lista: Army Roster, Boarding Actions, Crusade.
  ///
  /// `instanceOf` en general pregunta si una selección desciende de una entrada, que es otra cosa
  /// y no se sigue. Pero cuando lo que nombra es uno de los cuatro tipos de fuerza que declara el
  /// sistema, la pregunta es «¿de qué clase es esta lista?», y eso tiene respuesta exacta.
  bool _isForceTypeQuestion(Condition condition) =>
      (condition.type == 'instanceOf' || condition.type == 'notInstanceOf') &&
      faction.dataset.forces.any((f) => f.id == condition.childId);

  bool _holds(Condition condition, Selection target) {
    if (_isForceTypeQuestion(condition)) {
      final isThisForce = condition.childId == _force.id;
      return condition.type == 'instanceOf' ? isThisForce : !isThisForce;
    }

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
        // Incluye la configuración: el tamaño de partida y el detachment son selecciones de la
        // lista, y la mitad de las condiciones de ámbito roster preguntan justo por ellos.
        return expand([...units, ..._configuration]);
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
    uncheckedConstraints = 0;
    for (final selection in _all) {
      selection.uncheckedConstraints = 0;
    }
    final total = points;

    if (total > pointsLimit) {
      violations.add(Violation(null, 'La lista suma $total puntos y el límite es $pointsLimit'));
    }
    if (detachment == null) {
      violations.add(Violation(null, 'Falta elegir un detachment'));
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
        _check(child, child.count, constraint, child.modifiers, violations, child.name);
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
        _check(siblings.first, total, constraint, siblings.first.groupModifiers, violations,
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
        _check(unit, counts[unit.entryId] ?? 0, constraint, unit.modifiers, violations, unit.name);
      }
    }
  }

  void _check(Selection selection, int actual, Constraint constraint, List<Modifier> modifiers,
      List<Violation> violations, String subject) {
    final limit = _effectiveLimit(constraint, selection, modifiers);
    if (limit == null) return;

    final broken = constraint.isMax ? actual > limit : actual < limit;
    if (!broken) return;
    // El mensaje del dataset lleva el número declarado escrito. Si el efectivo es otro, no vale.
    final message = (limit == constraint.value ? constraint.message : null) ??
        (constraint.isMax ? 'como máximo $limit, hay $actual' : 'mínimo $limit, hay $actual');
    violations.add(Violation(selection, '$subject: $message'));
  }

  /// El límite que de verdad tiene una restricción, con los modifiers que la cambian aplicados.
  ///
  /// El número que declara el dataset no siempre es el que vale. Son 2.533 los modifiers que
  /// cambian una restricción de selecciones, y la mitad larga miran el tamaño de la partida: la
  /// mayoría de las unidades se pueden repetir tres veces en Strike Force y solo dos en Incursion,
  /// y quien lo dice es un `set 2` sobre la restricción, no la restricción.
  ///
  /// Devuelve `null` cuando hay un modifier que no se sabe evaluar. Entonces la restricción **no
  /// se comprueba**, en vez de comprobarse contra el número declarado: dar por ilegal una lista
  /// que no lo es sería peor que no avisar, y queda contado en [uncheckedConstraints].
  int? _effectiveLimit(Constraint constraint, Selection target, List<Modifier> modifiers) {
    var limit = constraint.value.round();
    for (final modifier in modifiers) {
      if (modifier.field != constraint.id) continue;
      if (!Modifier.numericTypes.contains(modifier.type)) continue;
      if (!_canEvaluate(modifier)) {
        uncheckedConstraints++;
        target.uncheckedConstraints++;
        return null;
      }
      if (!modifier.appliesWhen((c) => _holds(c, target))) continue;
      limit = modifier.applyTo(limit);
    }
    return limit;
  }

  /// Restricciones que [validate] ha dejado sin comprobar por no saber calcular su límite.
  ///
  /// Se cuenta desde cero en cada [validate]. Si no es cero, la lista puede tener incumplimientos
  /// que no se han visto; [selectionsWithUncheckedConstraints] dice en cuáles.
  int uncheckedConstraints = 0;

  /// Las selecciones con alguna restricción sin comprobar, para poder señalarlas en la interfaz.
  Iterable<Selection> get selectionsWithUncheckedConstraints =>
      _all.where((s) => s.uncheckedConstraints > 0);
}
