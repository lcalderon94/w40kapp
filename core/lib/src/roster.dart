import 'dataset.dart';
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
    required Map<String, int> baseCosts,
    this.count = 1,
    this.groupId,
    this.groupName,
    List<Selection>? children,
    List<Constraint>? constraints,
    List<Constraint>? groupConstraints,
    List<Modifier>? modifiers,
    List<Modifier>? groupModifiers,
    List<OptionGroup>? groups,
    List<String>? categoryIds,
    this.primaryCategoryId,
  })  : baseCosts = baseCosts,
        costs = {...baseCosts},
        children = children ?? [],
        constraints = constraints ?? const [],
        groupConstraints = groupConstraints ?? const [],
        modifiers = modifiers ?? const [],
        groupModifiers = groupModifiers ?? const [],
        groups = groups ?? const [],
        categoryIds = categoryIds ?? const [] {
    for (final child in this.children) {
      child.parent = this;
    }
  }

  final String entryId;
  final String name;

  /// `unit`, `model` o `upgrade`.
  final String type;

  /// Lo que declara el dataset que cuesta una instancia, por tipo de coste.
  ///
  /// No solo puntos: también Enhancements y Detachment Points, que son los que gasta la lista
  /// contra los presupuestos del ejército.
  final Map<String, int> baseCosts;

  /// Lo que cuesta de verdad una instancia, con los modifiers aplicados. Lo recalcula la lista.
  final Map<String, int> costs;

  int get basePointsEach => baseCosts[pointsCostTypeId] ?? 0;

  int get pointsEach => costs[pointsCostTypeId] ?? 0;

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

  /// Los grupos de opciones que ofrece esta selección, se haya elegido algo de ellos o no.
  final List<OptionGroup> groups;

  /// Categorías a las que pertenece. Las condiciones de los modifiers cuentan por categoría.
  final List<String> categoryIds;

  /// La categoría marcada como principal, que es el rol con el que se agrupa en la hoja de
  /// ejército. Las demás son palabras clave.
  final String? primaryCategoryId;

  Selection? parent;

  void addChild(Selection child) {
    child.parent = this;
    children.add(child);
  }

  /// Puntos de esta selección y de todo lo que cuelga de ella.
  int get points => costOf(pointsCostTypeId);

  /// Lo que esta selección y su descendencia gastan de un tipo de coste.
  int costOf(String typeId) =>
      (costs[typeId] ?? 0) * count +
      children.fold(0, (total, child) => total + child.costOf(typeId));

  /// Esta selección y toda su descendencia.
  Iterable<Selection> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }
}

/// Un grupo de opciones de una selección, con lo que el dataset exige de él.
///
/// Se guarda aunque no se haya elegido nada dentro: «entre 2 y 9 Blightlord Terminators» hay que
/// comprobarlo **también cuando hay cero**, que es justo cuando se incumple.
class OptionGroup {
  OptionGroup({
    required this.id,
    required this.name,
    required this.constraints,
    required this.modifiers,
    this.parentId,
    this.defaultId,
  });

  final String id;
  final String? name;
  final List<Constraint> constraints;
  final List<Modifier> modifiers;

  /// La opción que el dataset marca como equipo de serie de este grupo, si la marca.
  final String? defaultId;

  /// El grupo que contiene a este, si cuelga de otro.
  ///
  /// Los grupos anidan, y lo que se elige dentro de un subgrupo cuenta para el de fuera: el
  /// Campeón de la Plaga lleva «Wargear» con exactamente dos armas, y esas dos se eligen en dos
  /// subgrupos de una opción cada uno. Contando solo los hijos directos, «Wargear» ve cero por
  /// muy armado que esté el Campeón.
  final String? parentId;
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

  /// Los detachments elegidos, que son los que deciden las reglas del ejército.
  ///
  /// Son varios y no uno: el dataset deja el grupo en «mínimo 1, sin máximo» y lo que los limita
  /// es el presupuesto de Detachment Points, que en Onslaught da para dos.
  final List<Detachment> detachments = [];

  /// El primero de [detachments], que en casi todas las listas es el único.
  Detachment? get detachment => detachments.isEmpty ? null : detachments.first;

  set detachment(Detachment? value) {
    detachments
      ..clear()
      ..addAll([if (value != null) value]);
  }

  /// El tamaño de la partida.
  ///
  /// No es lo mismo que [pointsLimit], aunque cada tamaño traiga el suyo: **cambia las reglas de
  /// construcción**. Muchas unidades se pueden repetir tres veces en Strike Force y solo dos en
  /// Incursion, y eso lo decide un modifier sobre la restricción que mira cuál se ha elegido. Sin
  /// tamaño esos modifiers no se pueden evaluar y esos límites se quedan sin comprobar.
  BattleSize? battleSize;

  /// Los interruptores de «Show/Hide Options» que el jugador ha encendido.
  ///
  /// Vacío por defecto, que es lo que el dataset da por supuesto: sin encender nada, no hay
  /// unidades Legends, ni aliados, ni Imperial Agents, ni demonios. Ver [Dataset.visibilityOptions].
  final Set<String> shownOptions = {};

  /// El tipo de lista. Por defecto una partida normal, que es lo que asume el constructor.
  ///
  /// Hay reglas que solo valen en algunos: el máximo de Poxwalkers se dobla en Crusade, y las
  /// unidades de Boarding Actions se recortan a la mitad.
  Force? force;

  Force get _force => force ?? faction.dataset.standardForce;

  /// Las unidades que esta lista puede ofrecer de verdad.
  ///
  /// El dataset esconde el **76,7 %** de las unidades detrás de modifiers `hidden`: las Legends,
  /// los aliados, los Imperial Agents y los demonios que solo entran con según qué detachment
  /// —los Plaguebearers de una lista de Death Guard piden Tallyband Summoners—. Sin evaluarlos, el
  /// selector ofrece unidades que la lista no puede llevar, que es peor que no ofrecerlas: una
  /// lista se da por buena y no lo es.
  ///
  /// Cuando una condición no se sabe evaluar **no se esconde**, y se cuenta en
  /// [unresolvedVisibility]: esconder una unidad legal deja al jugador sin poder montar su lista,
  /// que es un daño mayor que dejar una de más a la vista.
  List<UnitEntry> get availableUnits {
    _forgetCategories();
    unresolvedVisibility = 0;
    return [
      for (final unit in faction.units)
        if (!_isHidden(unit)) unit,
    ];
  }

  /// La selección de partida de una unidad, ya sin lo que esta lista no puede llevar.
  ///
  /// [Dataset.selectionFor] despliega los mínimos mirando solo el dataset, y ahí entra equipo que
  /// depende del detachment: «Houndpack Lance Character» se colaba en cualquier lista de Chaos
  /// Knights y convertía a todos los War Dogs en Character, que es justo de lo que cuelgan unas
  /// mejoras que no tocaban.
  Selection selectionFor(UnitEntry unit) {
    _forgetCategories();
    final selection = faction.dataset.selectionFor(unit);
    _prune(selection);
    _completarMinimos(selection);
    return selection;
  }

  /// La única opción de un grupo capaz de cubrir ella sola lo que falta, si hay una sola así.
  ///
  /// Es como el dataset distingue al soldado raso del arma especial sin decirlo en ninguna parte:
  /// el raso no lleva techo o lo lleva alto, y las especiales lo llevan en una o dos. «Nueve
  /// Kabalite Warriors» ofrece cinco cosas y solo el guerrero raso puede ser nueve.
  ///
  /// Con más de una candidata no se elige por el jugador: ahí sí hay algo que decidir.
  Selection? _basicaDe(List<Selection> opciones, int faltan) {
    if (faltan < 1) return null;
    final candidatas = opciones.where((o) {
      int? tope;
      for (final c in o.constraints) {
        if (c.field != 'selections' || !c.isMax) continue;
        final v = c.value.round();
        if (v >= 0 && (tope == null || v < tope)) tope = v;
      }
      return tope == null || tope >= faltan;
    }).toList();
    return candidatas.length == 1 ? candidatas.single : null;
  }

  /// Rellena cada grupo hasta su mínimo **efectivo**, con la opción que el dataset marca de serie.
  ///
  /// El dataset ya rellena con el mínimo que trae escrito, pero ese no es el que se valida: los
  /// modifiers lo cambian —«un arma pesada por cada miniatura»— y el mínimo escrito puede ser 1
  /// cuando el que se exige son 2. Así la unidad nacía a medio equipar e incumpliendo por algo que
  /// el jugador no había decidido.
  ///
  /// Se pone de una en una y pasando por [canAdd], que es lo que respeta el techo de la propia
  /// opción: hay defectos con un máximo de 1 en grupos que piden nueve, y multiplicar sin mirar
  /// dejaba nueve donde cabía una.
  void _completarMinimos(Selection selection) {
    for (final group in selection.groups) {
      if (_groupHidden(selection, group)) continue;
      // Cuál es la opción de serie se decide una sola vez, con el mínimo entero del grupo. Si se
      // recalculara en cada vuelta, al faltar una sola valdrían todas —hasta las armas especiales
      // de tope uno— y dejaría de haber una candidata clara justo en el último hueco.
      final inicial = groupUsage(selection, group);
      if (inicial.minimo == null || inicial.puestas >= inicial.minimo!) continue;
      final delGrupo = optionsFor(selection).where((o) => o.groupId == group.id).toList();
      final opcion = group.defaultId != null
          ? delGrupo.where((o) => o.entryId == group.defaultId).firstOrNull
          : _basicaDe(delGrupo, inicial.minimo! - inicial.puestas);
      if (opcion == null) continue;

      // Hasta treinta intentos: es más que cualquier mínimo del dataset y evita que un límite mal
      // calculado deje esto dando vueltas.
      for (var intento = 0; intento < 30; intento++) {
        final uso = groupUsage(selection, group);
        if (uso.minimo == null || uso.puestas >= uso.minimo!) break;
        if (!canAdd(selection, opcion)) break;
        final puesta =
            selection.children.where((c) => c.entryId == opcion.entryId).firstOrNull;
        if (puesta != null) {
          puesta.count++;
        } else {
          selection.addChild(opcion);
        }
      }
    }
    // Y al revés: recortar lo que el relleno haya dejado por encima del techo efectivo. El
    // declarado y el efectivo no siempre coinciden —los modifiers bajan el tope según el tamaño de
    // la unidad— y sin esto la unidad nace pasada de su propio máximo sin que nadie lo haya
    // pedido. Solo al montarla: lo que ponga luego el jugador es cosa suya.
    for (final group in selection.groups) {
      for (var intento = 0; intento < 20; intento++) {
        final uso = groupUsage(selection, group);
        if (uso.maximo == null || uso.puestas <= uso.maximo!) break;
        final delGrupo = _groupAndNested(selection, group.id);
        final sobra = selection.children
            .where((c) => delGrupo.contains(c.groupId))
            .toList()
            .reversed
            .firstOrNull;
        if (sobra == null) break;
        if (sobra.count > 1) {
          sobra.count--;
        } else {
          selection.children.remove(sobra);
        }
      }
    }

    for (final child in selection.children) {
      _completarMinimos(child);
    }
  }

  void _prune(Selection selection) {
    selection.children.removeWhere((child) {
      child.parent = selection;
      return _applyHidden([...child.groupModifiers, ...child.modifiers], child);
    });
    for (final child in selection.children) {
      _prune(child);
    }
  }

  /// Lo que se le puede poner a una selección de esta lista.
  ///
  /// Lo mismo que [availableUnits] pero un nivel más abajo. El dataset esconde **el 52,8 % de las
  /// opciones**, casi siempre preguntando por el ancestro: comparte una lista de armas entre
  /// varias unidades y enseña en cada una solo las suyas. Ofrecerlas todas pone en la ficha de una
  /// unidad el equipo de otra.
  List<Selection> optionsFor(Selection selection) {
    _forgetCategories();
    final options = faction.dataset.optionsFor(selection);
    return [
      for (final option in options)
        if (!_isHiddenOption(option, selection)) option,
    ];
  }

  bool _isHiddenOption(Selection option, Selection parent) {
    // La opción todavía no cuelga de nada; para preguntar por el ancestro hay que colocarla.
    option.parent = parent;
    // Y cuentan los del grupo que la contiene: una mejora se esconde por lo que diga el grupo
    // «Enhancements», no por lo que diga ella. Mirando solo la opción, no se esconde ninguna.
    final hidden = _applyHidden([...option.groupModifiers, ...option.modifiers], option);
    option.parent = null;
    return hidden;
  }

  /// Condiciones de visibilidad que no se han sabido evaluar en la última llamada a
  /// [availableUnits] o [optionsFor]. Si no es cero, puede haber cosas de más en el selector.
  int unresolvedVisibility = 0;

  bool _isHidden(UnitEntry unit) {
    if (unit.visibility.isEmpty) return false;
    final candidate = Selection(
        entryId: unit.id, name: unit.name, type: unit.type, baseCosts: const {});
    return _applyHidden(unit.visibility, candidate);
  }

  /// Aplica en orden los modifiers de `hidden` sobre [target] y dice si queda escondido.
  ///
  /// Lo que no se sabe evaluar **no esconde**, y se cuenta: esconder algo legal deja al jugador
  /// sin poder montar su lista, que es peor que dejar una opción de más a la vista.
  bool _applyHidden(List<Modifier> modifiers, Selection target) {
    var hidden = false;
    for (final modifier in modifiers) {
      if (modifier.field != 'hidden' || modifier.type != 'set') continue;
      if (!_canEvaluate(modifier)) {
        unresolvedVisibility++;
        continue;
      }
      if (!modifier.appliesWhen((c) => _holds(c, target))) continue;
      hidden = modifier.value == true;
    }
    return hidden;
  }

  /// Coste de la lista, con los modifiers de coste ya aplicados.
  int get points {
    applyModifiers();
    final detachmentCost = detachments.fold(0, (total, d) => total + d.points);
    return units.fold(detachmentCost, (total, unit) => total + unit.points);
  }

  int get pointsRemaining => pointsLimit - points;

  void add(Selection unit) => units.add(unit);

  /// Recalcula el coste de cada selección aplicando los modifiers cuyas condiciones se cumplen.
  ///
  /// Sin esto una unidad de veinte Poxwalkers costaría lo mismo que una de diez: el dataset da 65
  /// como coste base y deja en un modifier que pase a 130 al superar las diez miniaturas.
  void applyModifiers() {
    _forgetCategories();
    skippedModifiers = 0;
    for (final selection in _all) {
      selection.costs
        ..clear()
        ..addAll(selection.baseCosts);
      selection.unresolvedCostModifiers = 0;
    }
    for (final selection in _all) {
      for (final modifier in selection.modifiers) {
        if (!selection.baseCosts.containsKey(modifier.field)) continue;
        if (!Modifier.numericTypes.contains(modifier.type)) continue;
        if (!_canEvaluate(modifier)) {
          skippedModifiers++;
          selection.unresolvedCostModifiers++;
          continue;
        }
        if (!modifier.appliesWhen(
            (c) => _holds(c, selection), (g) => _holdsLocal(g, selection))) continue;
        selection.costs[modifier.field] = modifier.applyTo(
            selection.costs[modifier.field] ?? 0,
            times: _timesFor(modifier, selection));
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
    final ids = [battleSize?.id, ...detachments.map((d) => d.id), ...shownOptions].nonNulls;
    final key = ids.join('|');
    if (_configurationKey == key) return _configurationCache;
    _configurationKey = key;
    return _configurationCache = [
      for (final id in ids)
        Selection(entryId: id, name: '', type: 'upgrade', baseCosts: const {}),
    ];
  }

  String? _configurationKey;
  List<Selection> _configurationCache = const [];

  /// Si el motor puede evaluar este modifier. Amplía [Modifier.isEvaluable] con lo que sabe la
  /// lista y no puede saber una condición suelta: de qué tipo es la fuerza.
  bool _canEvaluate(Modifier modifier) => modifier.isEvaluableWith((c) =>
      (c.isSupported ||
          _isInstanceQuestion(c) ||
          _isForceTypeQuestion(c) ||
          _isCatalogueQuestion(c) ||
          _isForceCountQuestion(c)) &&
      !_asksForUnknownBattleSize(c));

  /// `instanceOf` y `notInstanceOf` sobre un ámbito que sí se sabe recorrer.
  bool _isInstanceQuestion(Condition condition) =>
      (condition.type == 'instanceOf' || condition.type == 'notInstanceOf') &&
      Condition.supportedFields.contains(condition.field) &&
      !Condition.unsupportedScopes.contains(condition.scope);

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

  /// Si la condición cuenta **fuerzas** de un tipo: «cuántas fuerzas Crusade hay en el roster».
  ///
  /// Se contesta sin contar nada: una lista es una fuerza y de un solo tipo, así que la cuenta es
  /// uno o cero. Darlo por no evaluable tiraba el modifier entero aunque el resto de sus
  /// condiciones sí se supieran, y con él se caían gates que sí importan: el Dark Commune de los
  /// Chaos Knights pide Iconoclast Fiefdom **y** no ser Crusade, y al no saber lo segundo se
  /// ofrecía con cualquier detachment.
  bool _isForceCountQuestion(Condition condition) =>
      condition.field == 'forces' &&
      faction.dataset.forces.any((f) => f.id == condition.childId);

  /// Si la condición pregunta de qué facción es la lista.
  ///
  /// El ámbito `primary-catalogue` no se recorre contando nada: nombra el catálogo principal, y
  /// una lista tiene uno solo. Es la misma pregunta que separa los detachments de cada capítulo de
  /// Space Marines, y la que decide si media facción se enseña o se esconde: son 2.661 condiciones
  /// de visibilidad, la mayoría de las que había sin evaluar.
  bool _isCatalogueQuestion(Condition condition) =>
      condition.scope == 'primary-catalogue' &&
      (condition.type == 'instanceOf' || condition.type == 'notInstanceOf');

  bool _holds(Condition condition, Selection target) {
    if (_isForceCountQuestion(condition)) {
      final esta = condition.childId == _force.id ? 1 : 0;
      return condition.type == 'instanceOf'
          ? esta == 1
          : condition.type == 'notInstanceOf'
              ? esta == 0
              : condition.holdsFor(esta);
    }
    if (_isCatalogueQuestion(condition)) {
      final isThisCatalogue = condition.childId == faction.id;
      return condition.type == 'instanceOf' ? isThisCatalogue : !isThisCatalogue;
    }
    if (_isForceTypeQuestion(condition)) {
      final isThisForce = condition.childId == _force.id;
      return condition.type == 'instanceOf' ? isThisForce : !isThisForce;
    }

    // Solo se saben contar selecciones y puntos; otros tipos de coste aún no se siguen.
    if (condition.field != 'selections' && condition.field != pointsCostTypeId) return false;

    if (condition.type == 'instanceOf' || condition.type == 'notInstanceOf') {
      final hay = _instanceScopeOf(condition.scope, target)
          .any((s) => _matches(condition.childId, s));
      return condition.type == 'instanceOf' ? hay : !hay;
    }

    return condition.holdsFor(_count(
      field: condition.field,
      scope: condition.scope,
      childId: condition.childId,
      includeChildSelections: condition.includeChildSelections,
      target: target,
    ));
  }

  /// Si se cumple un grupo que mira a los hermanos y a su orden.
  ///
  /// Cuenta cuántas selecciones del ámbito van **antes** que esta y son de la misma hoja de datos,
  /// que es como el dataset sube el precio de las copias repetidas: el segundo Plagueburst Crawler
  /// vale 30 puntos más que el primero, y el tercer Great Unclean One 15 más que el segundo.
  bool _holdsLocal(LocalConditionGroup group, Selection target) {
    final hermanos = switch (group.scope) {
      'parent' => target.parent?.children ?? units,
      _ => units,
    };
    final donde = hermanos.indexOf(target);
    // Si no está en la lista todavía —una opción que aún no se ha puesto— cuentan todos.
    final hasta = donde < 0 || !group.ordered ? hermanos.length : donde;

    var cuantos = 0;
    for (var i = 0; i < hasta; i++) {
      final otro = hermanos[i];
      if (identical(otro, target)) continue;
      final pega = otro.descendantsAndSelf.any((s) => group.matches.contains(s.entryId));
      if (pega) cuantos += otro.count;
    }
    return group.holdsFor(cuantos);
  }

  /// Cuántas veces hay que aplicar un modifier, según sus proporciones.
  ///
  /// Sin `repeats` va una vez. Con ellas, tantas como digan: «una menos por cada Starcannon».
  int _timesFor(Modifier modifier, Selection target) {
    if (modifier.repeats.isEmpty) return 1;
    var times = 0;
    for (final repeat in modifier.repeats) {
      times += repeat.timesFor(_count(
        field: repeat.field,
        scope: repeat.scope,
        childId: repeat.childId,
        includeChildSelections: repeat.includeChildSelections,
        target: target,
      ));
    }
    return times;
  }

  /// Lo que hay en un ámbito: número de selecciones, o puntos que suman.
  int _count({
    required String field,
    required String scope,
    required String childId,
    required bool includeChildSelections,
    required Selection target,
  }) {
    final counted = _scopeOf(scope, includeChildSelections, target)
        .where((s) => _matches(childId, s));
    return field == 'selections'
        ? counted.fold<int>(0, (total, s) => total + s.count)
        : counted.fold<int>(0, (total, s) => total + s.pointsEach * s.count);
  }

  /// A quién se refiere un `instanceOf`, que no es lo mismo que dónde se cuenta.
  ///
  /// «¿El padre es un Psyker?» pregunta por el padre; «¿cuántas selecciones hay en el padre?»
  /// pregunta por sus hijos. Mezclarlas hace que una mejora se esconda porque la unidad que la
  /// lleva no tiene ningún hijo con la palabra clave —la tiene ella—, y así desaparecen todas.
  Iterable<Selection> _instanceScopeOf(String scope, Selection target) {
    switch (scope) {
      case 'self':
        return [target];
      case 'parent':
        return [if (target.parent != null) target.parent!];
      case 'ancestor':
        return _ancestorsOf(target);
      case 'root-entry':
        return [_ancestorsOf(target).lastOrNull ?? target];
      case 'unit':
      case 'model':
        return [target, ..._ancestorsOf(target)].where((s) => s.type == scope);
      case 'force':
      case 'roster':
        return [...units.expand((u) => u.descendantsAndSelf), ..._configuration];
      default:
        return _scopeOf(scope, true, target);
    }
  }

  /// Los padres de una selección, del más cercano al más lejano.
  Iterable<Selection> _ancestorsOf(Selection selection) sync* {
    var parent = selection.parent;
    while (parent != null) {
      yield parent;
      parent = parent.parent;
    }
  }

  Iterable<Selection> _scopeOf(String scope, bool includeChildSelections, Selection target) {
    Iterable<Selection> expand(Iterable<Selection> roots) =>
        includeChildSelections ? roots.expand((s) => s.descendantsAndSelf) : roots;

    switch (scope) {
      case 'self':
        return expand([target]);
      case 'parent':
        // El padre de una selección de primer nivel es la propia fuerza, no la nada: el dataset
        // escribe «menos de un Final Day en el padre» para preguntar por el detachment de la
        // lista, y devolviendo vacío la cuenta salía cero y la unidad se escondía siempre.
        final siblings = target.parent?.children;
        return expand(siblings ?? [...units, ..._configuration]);
      case 'force':
      case 'roster':
        // Incluye la configuración: el tamaño de partida y el detachment son selecciones de la
        // lista, y la mitad de las condiciones de ámbito roster preguntan justo por ellos.
        return expand([...units, ..._configuration]);
      case 'ancestor':
        // La cadena de padres, sin contarse a sí misma. Es como el dataset comparte una lista de
        // opciones entre varias unidades y enseña en cada una solo las suyas: «esta arma se
        // esconde si ningún ancestro es Howling Banshees».
        return _ancestorsOf(target);
      case 'root-entry':
        final root = _ancestorsOf(target).lastOrNull ?? target;
        return expand([root]);
      case 'unit':
      case 'model':
        final owner = [target, ..._ancestorsOf(target)]
            .where((s) => s.type == scope)
            .firstOrNull;
        return owner == null ? const [] : expand([owner]);
      default:
        // El ámbito es el id de un grupo de opciones o de otra entrada.
        final inGroup = target.descendantsAndSelf.where((s) => s.groupId == scope);
        if (inGroup.isNotEmpty) return expand(inGroup);
        final entry = _all.where((s) => s.entryId == scope);
        return entry.isEmpty ? const [] : expand(entry.first.children);
    }
  }

  bool _matches(String childId, Selection selection) => switch (childId) {
        'any' => true,
        'model' || 'unit' || 'upgrade' => selection.type == childId,
        _ => selection.entryId == childId || categoriesOf(selection).contains(childId),
      };

  /// Las palabras clave que de verdad tiene una selección en esta lista.
  ///
  /// No son las que trae escritas: hay 1.252 modifiers que las cambian, y muchos dependen del
  /// detachment. Houndpack Lance convierte a los War Dogs en **Character**, y de eso cuelgan las
  /// mejoras que solo ellos pueden llevar; con las declaradas a secas, esas mejoras no aparecen en
  /// ninguna unidad.
  ///
  /// Las condiciones de estos modifiers se evalúan con las categorías **declaradas**, no con las
  /// ya calculadas, para no morderse la cola. Se puede: de las 544 condiciones que tienen, solo 7
  /// preguntan por una categoría.
  List<String> categoriesOf(Selection selection) {
    final cached = _categoryCache[selection];
    if (cached != null) return cached;

    final categories = [...selection.categoryIds];
    if (!_resolvingCategories) {
      _resolvingCategories = true;
      try {
        // Las suyas, y las que le suben de lo que lleva puesto: hay opciones que existen solo para
        // dar una palabra clave —«Houndpack Lance Character» convierte al War Dog en Character— y
        // sin recogerlas la unidad nunca cumple los gates que dependen de ella.
        for (final node in selection.descendantsAndSelf) {
          for (final modifier in node.modifiers) {
            if (modifier.field != 'category') continue;
            final category = modifier.value;
            if (category is! String) continue;
            if (!_canEvaluate(modifier)) continue;
            if (!modifier.appliesWhen((c) => _holds(c, node))) continue;
            switch (modifier.type) {
              case 'add':
              case 'set-primary':
                if (!categories.contains(category)) categories.add(category);
              case 'remove':
                if (identical(node, selection)) categories.remove(category);
              // `unset-primary` deja de ser la principal, pero la palabra clave sigue estando.
            }
          }
        }
      } finally {
        _resolvingCategories = false;
      }
    }
    return _categoryCache[selection] = categories;
  }

  final _categoryCache = <Selection, List<String>>{};
  bool _resolvingCategories = false;

  /// Se vacía al empezar cualquier cálculo: las categorías dependen de la configuración de la
  /// lista, así que dejarlas cacheadas entre detachments daría respuestas del anterior.
  void _forgetCategories() => _categoryCache.clear();

  /// Comprueba la legalidad de la lista.
  ///
  /// Cubre el límite de puntos y las restricciones de número de selecciones: los mínimos y máximos
  /// de cada opción, los de su grupo, y los que limitan cuántas veces puede repetirse una unidad en
  /// el ejército. No cubre todavía los modifiers que cambian restricciones en vez de costes, ni los
  /// límites por rol del destacamento.
  List<Violation> validate() {
    _forgetCategories();
    final violations = <Violation>[];
    uncheckedConstraints = 0;
    for (final selection in _all) {
      selection.uncheckedConstraints = 0;
    }
    final total = points;

    if (total > pointsLimit) {
      violations.add(Violation(null, 'La lista suma $total puntos y el límite es $pointsLimit'));
    }
    if (detachments.isEmpty) {
      violations.add(Violation(null, 'Falta elegir un detachment'));
    }

    for (final unit in units) {
      _validateSelection(unit, violations);
    }
    _validateArmyWide(violations);
    _validateForce(violations);
    return violations;
  }

  /// Cuántos Detachment Points permite el tamaño de partida, o `null` si no se sabe.
  ///
  /// Son 2 por defecto, 3 en Strike Force y 4 en Onslaught, y no está escrito a mano: lo declara
  /// la fuerza y lo cambian modifiers según el tamaño elegido.
  int? get detachmentPointsBudget {
    final node = _force.node;
    if (node.isEmpty) return null;
    final modifiers = Modifier.allOf(node);
    final reference = _configuration.isEmpty
        ? Selection(entryId: '', name: '', type: 'upgrade', baseCosts: const {})
        : _configuration.first;
    for (final constraint in _force.constraints) {
      if (constraint.field != Dataset.detachmentPointsCostTypeId || !constraint.isMax) continue;
      final limit = _effectiveLimit(constraint, reference, modifiers);
      if (limit != null && limit >= 0) return limit;
    }
    return null;
  }

  /// Las reglas que la propia fuerza pone al ejército entero.
  ///
  /// No son de ninguna unidad: las declara el tipo de lista, y en 11ª son tres. El presupuesto de
  /// **Detachment Points** —2 por defecto, 3 en Strike Force, 4 en Onslaught—, cuántas
  /// **Enhancements** caben —2 en Incursion, 4 en el resto— y el límite de puntos, que aquí se
  /// deja fuera porque ya lo comprueba [pointsLimit] con un mensaje mejor.
  ///
  /// Se leen del dataset en vez de escribirlas a mano, así que si upstream cambia un presupuesto
  /// esto lo sigue sin tocar nada.
  void _validateForce(List<Violation> violations) {
    final node = _force.node;
    if (node.isEmpty) return;
    final modifiers = Modifier.allOf(node);
    // Un ámbito de la fuerza necesita algo a lo que referirse; la configuración vale, porque las
    // condiciones de estas reglas preguntan justo por ella (qué tamaño de partida se ha elegido).
    final reference = _configuration.isEmpty
        ? Selection(entryId: '', name: '', type: 'upgrade', baseCosts: const {})
        : _configuration.first;

    for (final constraint in _force.constraints) {
      if (constraint.field == 'selections' || constraint.field == pointsCostTypeId) continue;
      final limit = _effectiveLimit(constraint, reference, modifiers);
      if (limit == null || limit < 0) continue;

      final actual = units.fold(0, (total, unit) => total + unit.costOf(constraint.field)) +
          (constraint.field == Dataset.detachmentPointsCostTypeId
              ? detachments.fold(0, (total, d) => total + d.detachmentPoints)
              : 0);
      final broken = constraint.isMax ? actual > limit : actual < limit;
      if (!broken) continue;
      violations.add(Violation(
          null,
          constraint.message?.replaceAll('{value}', '$limit') ??
              (constraint.isMax
                  ? 'como máximo $limit, hay $actual'
                  : 'mínimo $limit, hay $actual')));
    }
  }

  void _validateSelection(Selection selection, List<Violation> violations) {
    for (final child in selection.children) {
      for (final constraint in child.constraints) {
        if (constraint.field != 'selections') continue;
        if (constraint.scope != 'parent' && constraint.scope != 'self') continue;
        _check(child, child.count, constraint, child.modifiers, violations, child.name);
      }
    }

    // Las restricciones del grupo se cumplen entre todos los hermanos que salen de él, y se
    // comprueban aunque no haya ninguno: un grupo vacío es justo el que incumple su mínimo.
    for (final group in selection.groups) {
      // Un grupo escondido no exige nada. El dataset esconde grupos enteros según el detachment
      // —las Marcas del Caos solo existen con Pactbound Zealots— y entonces esconde también sus
      // opciones. Validando el grupo igual, la unidad pedía elegir de una lista vacía: un
      // incumplimiento imposible de arreglar.
      if (_groupHidden(selection, group)) continue;

      // Lo elegido en un subgrupo cuenta para el grupo de fuera. Si no, un grupo que solo contiene
      // subgrupos —«Wargear: exactamente dos armas», repartidas en dos subgrupos de una— se ve
      // siempre vacío y avisa de un incumplimiento que no existe.
      final delGrupo = _groupAndNested(selection, group.id);
      final fromGroup =
          selection.children.where((c) => delGrupo.contains(c.groupId)).toList();
      final total = fromGroup.fold(0, (sum, s) => sum + s.count);
      // Las condiciones de ámbito `parent` cuentan sobre los hermanos, así que hace falta mirar
      // desde dentro del grupo. Cuando está vacío se usa un hueco colgado de la misma selección.
      final desde = fromGroup.isNotEmpty
          ? fromGroup.first
          : (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = selection);
      for (final constraint in group.constraints) {
        if (constraint.field != 'selections') continue;
        // Se evalúa desde dentro del grupo, pero el aviso se le achaca a la unidad: es la que el
        // jugador tiene que abrir para arreglarlo, y el hueco no está en ninguna lista.
        _check(desde, total, constraint, group.modifiers, violations,
            group.name ?? selection.name, blame: selection);
      }
    }

    for (final child in selection.children) {
      _validateSelection(child, violations);
    }
  }

  /// Si el dataset esconde este grupo en esta lista.
  bool _groupHidden(Selection owner, OptionGroup group) {
    final delGrupo = _groupAndNested(owner, group.id);
    final desde = owner.children.where((c) => delGrupo.contains(c.groupId)).firstOrNull ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);
    return _applyHidden(group.modifiers, desde);
  }

  /// El grupo y todos los que anidan dentro de él, por id.
  Set<String> _groupAndNested(Selection selection, String groupId) {
    final ids = {groupId};
    var crecio = true;
    while (crecio) {
      crecio = false;
      for (final g in selection.groups) {
        if (g.parentId != null && ids.contains(g.parentId) && ids.add(g.id)) crecio = true;
      }
    }
    return ids;
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
      List<Violation> violations, String subject, {Selection? blame}) {
    final limit = _effectiveLimit(constraint, selection, modifiers);
    if (limit == null) return;
    // Un límite negativo es «sin límite»: así lo escribe el dataset en 48 restricciones.
    if (limit < 0) return;

    final broken = constraint.isMax ? actual > limit : actual < limit;
    if (!broken) return;
    // El mensaje del dataset lleva el número declarado escrito. Si el efectivo es otro, no vale.
    final message = (limit == constraint.value ? constraint.message : null) ??
        (constraint.isMax ? 'como máximo $limit, hay $actual' : 'mínimo $limit, hay $actual');
    violations.add(Violation(blame ?? selection, '$subject: $message'));
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
      limit = modifier.applyTo(limit, times: _timesFor(modifier, target));
    }
    return limit;
  }

  /// Cuántas cosas cabe elegir de un grupo, y cuántas hay puestas.
  ///
  /// El límite no es el número que trae escrito la restricción: el dataset lo cambia con modifiers
  /// —«un arma pesada por cada cinco miniaturas»— y pintar el declarado enseña un tope que no es
  /// el que se aplica. `null` en un tope significa que no lo hay o que no se ha sabido calcular,
  /// que para la interfaz es lo mismo: no lo enseña en vez de enseñar uno falso.
  ({int puestas, int? minimo, int? maximo}) groupUsage(Selection owner, OptionGroup group) {
    final delGrupo = _groupAndNested(owner, group.id);
    final dentro = owner.children.where((c) => delGrupo.contains(c.groupId)).toList();
    final puestas = dentro.fold<int>(0, (t, s) => t + s.count);
    final desde = dentro.isNotEmpty
        ? dentro.first
        : (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);

    int? minimo, maximo;
    for (final constraint in group.constraints) {
      if (constraint.field != 'selections') continue;
      final limit = _effectiveLimit(constraint, desde, group.modifiers);
      if (limit == null || limit < 0) continue;
      if (constraint.isMax) {
        maximo = maximo == null || limit < maximo ? limit : maximo;
      } else {
        minimo = minimo == null || limit > minimo ? limit : minimo;
      }
    }
    return (puestas: puestas, minimo: minimo, maximo: maximo);
  }

  /// Si cabe una más de esa opción bajo [owner].
  ///
  /// El dataset pone techos en dos sitios y hay que mirar los dos: en la propia opción («un
  /// Rotwind, no veinte») y en el grupo del que sale («como mucho dos armas especiales»). Sin
  /// esto la interfaz deja pulsar el `+` para siempre y la lista se va a ilegal sin avisar de
  /// nada hasta el final.
  ///
  /// Un grupo que solo deja elegir una cosa es la excepción: ahí elegir **sustituye**, así que
  /// siempre cabe.
  bool canAdd(Selection owner, Selection option) {
    final puestas = owner.children
        .where((c) => c.entryId == option.entryId)
        .fold<int>(0, (t, c) => t + c.count);

    final desde = owner.children.where((c) => c.entryId == option.entryId).firstOrNull ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);

    for (final constraint in option.constraints) {
      if (constraint.field != 'selections' || !constraint.isMax) continue;
      if (constraint.scope != 'parent' && constraint.scope != 'self') continue;
      final limit = _effectiveLimit(constraint, desde, option.modifiers);
      if (limit != null && limit >= 0 && puestas >= limit) return false;
    }

    if (option.groupId == null) return true;
    final grupo = owner.groups.where((g) => g.id == option.groupId).firstOrNull;
    if (grupo == null) return true;
    final uso = groupUsage(owner, grupo);
    if (uso.maximo == null) return true;
    if (uso.maximo == 1) return true; // se sustituye, no se apila
    return uso.puestas < uso.maximo!;
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
