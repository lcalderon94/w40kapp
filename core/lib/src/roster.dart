import 'dataset.dart';
import 'detachment.dart';
import 'model.dart';
import 'modifiers.dart';
import 'topes.dart';

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

  /// El nombre que le ha puesto el jugador, si le ha puesto alguno.
  ///
  /// «La Guardia Podrida» en vez de «Blightlord Terminators»: en una lista con tres escuadras
  /// iguales es la única forma de saber cuál es cuál.
  String? customName;

  /// Cómo se llama en la lista: el suyo propio si lo tiene, y si no el de su hoja de datos.
  String get displayName => customName?.isNotEmpty == true ? customName! : name;

  /// La unidad a la que este líder se ha unido, si se ha unido a alguna.
  ///
  /// No cuelga de ella —cada una sigue pagando sus puntos y llevando su equipo— pero se juega y se
  /// enseña como una sola cosa, que es lo que dice la regla Leader.
  Selection? attachedTo;

  void addChild(Selection child) {
    child.parent = this;
    children.add(child);
  }

  /// Lo que hay puesto de esa opción, **en su grupo**.
  ///
  /// La misma arma aparece en dos grupos distintos de la misma unidad: el Defiler ofrece el
  /// Electroscourge tanto para sustituir el lanzamisiles como para sustituir el baleflamer, y es
  /// la misma entrada. Buscando solo por entrada, marcar una marcaba las dos —dos casillas de una
  /// sola pulsación— y quitar una dejaba al otro grupo sin nada. Pasa en 295 unidades del dataset,
  /// con 764 opciones repartidas así.
  Selection? puestaDe(Selection option) => children
      .where((c) => c.entryId == option.entryId && c.groupId == option.groupId)
      .firstOrNull;

  /// Cuántas hay puestas de esa opción, en su grupo.
  int cuantasDe(Selection option) => children
      .where((c) => c.entryId == option.entryId && c.groupId == option.groupId)
      .fold(0, (total, c) => total + c.count);

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
      // Qué se pone: lo que el dataset marca de serie; si no marca nada, la única opción capaz de
      // cubrir el grupo ella sola; y si tampoco hay una clara, la primera que ofrezca.
      //
      // Esa última es una decisión y conviene decirla: un hueco obligatorio vacío deja la unidad
      // ilegal desde que entra y obliga a ir a buscarlo, mientras que una elección puesta se ve y
      // se cambia de un toque. Entre las dos, poner algo es lo que se espera de un constructor.
      //
      // Y si lo que marca de serie no está entre lo que ofrece, se elige igual: el Desolation
      // Sergeant apunta a un id que no es ninguna de sus dos opciones, y dándolo por imposible la
      // unidad entraba en la lista ya ilegal —«Weapon Option: mínimo 1, hay 0»— nada más añadirla.
      final opcion = (group.defaultId != null
              ? delGrupo.where((o) => o.entryId == group.defaultId).firstOrNull
              : null) ??
          _basicaDe(delGrupo, inicial.minimo! - inicial.puestas) ??
          delGrupo.firstOrNull;
      if (opcion == null) continue;

      // Hasta treinta intentos: es más que cualquier mínimo del dataset y evita que un límite mal
      // calculado deje esto dando vueltas.
      for (var intento = 0; intento < 30; intento++) {
        final uso = groupUsage(selection, group);
        if (uso.minimo == null || uso.puestas >= uso.minimo!) break;
        if (!canAdd(selection, opcion)) break;
        final puesta = selection.puestaDe(opcion);
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

  /// De qué facción aliada es esta unidad, o `null` si es de la propia.
  ///
  /// Los Chaos Knights no son de la Death Guard, ni los Imperial Knights ni los inquisidores de
  /// Agents of the Imperium son de nadie más: son **aliados**, y meterlos en Personajes o Vehículos
  /// junto a los propios es mezclar dos cosas distintas. El dataset ya lo dice y no hacía falta
  /// inventarlo: cada unidad de un catálogo aliado lleva un `set-primary` a una categoría
  /// «Allies: …» condicionado a que el catálogo principal **no** sea el suyo. En una lista de
  /// Chaos Knights ese modifier no se cumple y los War Dogs vuelven a ser Character, que es lo
  /// correcto: allí son la facción.
  String? allyOf(UnitEntry unit) {
    // Unas lo traen declarado sin necesidad de modifier —las fortificaciones y los vehículos de
    // Unaligned Forces, que no son de nadie— y otras se lo ponen con un modifier según de quién
    // sea la lista. Hay que mirar las dos cosas.
    for (final keyword in unit.keywords) {
      if (keyword.startsWith('Allies:')) {
        return keyword.substring('Allies:'.length).trim();
      }
    }
    if (unit.categoryModifiers.isEmpty) return null;
    final candidate = Selection(
        entryId: unit.id,
        name: unit.name,
        type: unit.type,
        baseCosts: const {});
    String? ally;
    for (final modifier in unit.categoryModifiers) {
      final category = modifier.value;
      if (category is! String) continue;
      final name = faction.dataset.allyCategories[category];
      if (name == null) continue;
      if (!_canEvaluate(modifier)) continue;
      if (!modifier.appliesWhen((c) => _holds(c, candidate))) continue;
      switch (modifier.type) {
        case 'add':
        case 'set-primary':
          ally = name;
        case 'remove':
          if (ally == name) ally = null;
      }
    }
    return ally;
  }

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

  /// Quita una unidad y separa lo que estuviera unido a ella, para no dejar huérfanos.
  void remove(Selection unit) {
    for (final otra in units) {
      if (otra.attachedTo == unit) otra.attachedTo = null;
    }
    units.remove(unit);
  }

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

  /// Si una selección es «de las que cuenta» una condición.
  ///
  /// El `childId` de una condición puede nombrar tres cosas y hay que reconocer las tres: una
  /// entrada, una categoría **o un grupo de opciones**. Lo tercero faltaba, y es como el dataset
  /// cuenta el tamaño de una escuadra: «si hay 6 o más selecciones del grupo Terminators, esta
  /// unidad cuesta 320 en vez de 160». Sin reconocerlo, una escuadra de diez Terminators se
  /// cobraba como una de cinco.
  bool _matches(String childId, Selection selection) => switch (childId) {
        'any' => true,
        'model' || 'unit' || 'upgrade' => selection.type == childId,
        _ => selection.entryId == childId ||
            selection.groupId == childId ||
            categoriesOf(selection).contains(childId),
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

  /// Las unidades a las que este líder puede unirse **y que están en la lista**.
  ///
  /// Una que ya lleve líder no vale: la regla deja uno por unidad.
  List<Selection> hostsFor(Selection leader) {
    final entrada = faction.units.where((u) => u.id == leader.entryId).firstOrNull;
    if (entrada == null) return const [];
    final permitidos =
        faction.dataset.leaderTargets(faction, entrada).map((u) => u.id).toSet();
    if (permitidos.isEmpty) return const [];

    // Una unidad lleva un líder de cada clase —Leader y Support—, no los que se le pongan. La
    // regla 19.01 lo dice así, y ocho hojas traen su propia excepción escrita para llevar dos del
    // mismo: Cato Sicarius, el Castellan, el Sanguinary Priest, el Warlock… Sin este filtro se
    // podían encadenar cuatro, veinte, los que hubiera en la lista, uno detrás de otro.
    return [
      for (final u in units)
        if (u != leader && permitidos.contains(u.entryId) && !hostAlreadyLed(leader, u)) u,
    ];
  }

  /// Si esa unidad ya lleva algo de la misma clase que este líder, y el líder no trae excepción.
  ///
  /// No impide unirlo: lo señala, que es lo que el jugador necesita para decidir.
  bool hostAlreadyLed(Selection leader, Selection host) {
    final entrada = faction.units.where((u) => u.id == leader.entryId).firstOrNull;
    if (entrada == null) return false;

    // El techo de verdad, y por delante de cualquier excepción: en ninguna hoja del juego van
    // tres líderes sobre la misma unidad. Sin esto, dos excepciones distintas se colaban juntas
    // —cada una se justifica con la suya propia, sin mirar cuántas hay ya— y una Crusader Squad
    // terminaba con cuatro encima: el Chaplain, el Castellan, el Crusade Ancient y el Apothecary.
    final yaTiene = units.where((o) => o.attachedTo == host && o != leader).length;
    if (yaTiene >= 2) return true;

    if (faction.dataset.aceptaOtroLider(entrada)) return false;
    final clase = faction.dataset.attachKind(entrada);
    return units.any((o) =>
        o.attachedTo == host &&
        o != leader &&
        _claseDe(o) == clase &&
        !_aceptaOtro(o));
  }

  /// Si el que ya está unido trae la excepción, no estorba al siguiente.
  bool _aceptaOtro(Selection s) {
    final entrada = faction.units.where((u) => u.id == s.entryId).firstOrNull;
    return entrada != null && faction.dataset.aceptaOtroLider(entrada);
  }

  String? _claseDe(Selection s) {
    final entrada = faction.units.where((u) => u.id == s.entryId).firstOrNull;
    return entrada == null ? null : faction.dataset.attachKind(entrada);
  }

  /// Une un líder a una unidad, o lo separa si [host] es nulo.
  ///
  /// Con el mismo candado que [hostsFor]: por si algo llega a llamarlo sin pasar por la lista ya
  /// filtrada, aquí no se deja la unión igual.
  void attach(Selection leader, Selection? host) {
    if (host != null && hostAlreadyLed(leader, host)) return;
    leader.attachedTo = host;
  }

  /// Los líderes unidos a esta unidad.
  Iterable<Selection> leadersOn(Selection host) =>
      units.where((u) => u.attachedTo == host);

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

  /// Cuántas miniaturas tiene de verdad la escuadra, y entre qué números puede moverse.
  ///
  /// No es lo mismo que [groupUsage]. El dataset saca al sargento del grupo: una escuadra de
  /// Plague Marines es «Plague Champion» —hijo suelto, uno y solo uno— más el grupo «Plague
  /// Marines», que va de cuatro a nueve. Enseñar las puestas del grupo a secas decía **9** en una
  /// escuadra de diez, y es el número que el jugador compara con la hoja. Pasaba en **223 de las
  /// 1.085 unidades con escuadra**.
  ///
  /// Los botones siguen trabajando sobre el grupo, que es lo único que se puede tocar; lo que
  /// cambia es el número que se lee.
  ({int puestas, int? minimo, int? maximo}) squadTally(Selection owner, OptionGroup group) {
    final uso = groupUsage(owner, group);
    if (mainModelGroup(owner)?.id != group.id) return uso;

    // Todo lo que es una miniatura y no lo cuenta ya nadie: el sargento, esté suelto —Blightlord
    // Champion— o metido en un grupo suyo de uno —Terminator Champion—. Las dos formas las usa el
    // dataset y las dos son la misma escuadra.
    //
    // Fuera quedan dos cosas, que contarlas aquí sería contarlas dos veces: lo que ya entra en el
    // recuento del propio grupo —sus subgrupos, como el «Special Weapon» de los Kroot— y lo que
    // tiene barra propia porque el jugador lo dimensiona aparte —los Neophytes de una Crusader
    // Squad—.
    final yaContado = _groupAndNested(owner, group.id);
    final aparte = <String>{};
    for (final g in owner.groups) {
      if (yaContado.contains(g.id)) continue;
      if (!isModelGroup(owner, g)) continue;
      if (_sePuedeRedimensionar(owner, g)) aparte.add(g.id);
    }
    var fijas = 0;
    for (final hijo in owner.children) {
      if (hijo.groupId != null &&
          (yaContado.contains(hijo.groupId) || aparte.contains(hijo.groupId))) {
        continue;
      }
      if (hijo.type != 'model') continue;
      fijas += hijo.count;
    }
    return (
      puestas: uso.puestas + fijas,
      minimo: uso.minimo == null ? null : uso.minimo! + fijas,
      maximo: uso.maximo == null ? null : uso.maximo! + fijas,
    );
  }

  /// El grupo que **es** la escuadra, cuando hay varios de miniaturas: el que el jugador dimensiona.
  ///
  /// El del sargento también es un grupo de miniaturas y también lleva una, así que hace falta un
  /// criterio fijo para no contar dos veces. Manda el que más miniaturas tiene puestas —la tropa
  /// es la escuadra y el sargento es uno—, y a igualdad el que declara techo de más de uno.
  OptionGroup? mainModelGroup(Selection owner) {
    OptionGroup? mejor;
    var suyas = 0;
    var suTecho = 0;
    for (final g in owner.groups) {
      if (!isModelGroup(owner, g)) continue;
      final uso = groupUsage(owner, g);
      // Sin nada puesto y sin mínimo no es una escuadra, es un grupo de armas especiales cuyo
      // relleno de serie vive fuera —los Skitarii Rangers llevan «w/ galvanic rifle» suelto, sin
      // grupo, y «Skitarii Rangers Options» solo ofrece las alternativas—. Contándolo como
      // principal salía un «+» que no crecía nada y el precio se quedaba clavado: 85 y 85.
      if (uso.puestas <= 0 && (uso.minimo ?? 0) <= 0) continue;
      final techo = uso.maximo ?? 1 << 20;
      if (uso.puestas > suyas || (mejor == null) || (uso.puestas == suyas && techo > suTecho)) {
        mejor = g;
        suyas = uso.puestas;
        suTecho = techo;
      }
    }
    return mejor;
  }

  /// Si las miniaturas de este grupo ya las cuenta la barra de la escuadra principal.
  ///
  /// El grupo sigue pintándose —ahí están las armas del sargento— pero sin su propio contador, que
  /// es lo que hacía que una escuadra de diez se leyera como «9 Terminators» y «1 Champion» en dos
  /// cajas, en vez de «10 Chaos Terminators» como pone la hoja.
  bool foldedIntoMainSquad(Selection owner, OptionGroup group) {
    if (!isModelGroup(owner, group)) return false;
    if (mainModelGroup(owner)?.id == group.id) return false;
    return !_sePuedeRedimensionar(owner, group);
  }

  bool _sePuedeRedimensionar(Selection owner, OptionGroup group) {
    if (shrinkTarget(owner, group) != null) return true;
    final uso = groupUsage(owner, group);
    if (uso.maximo != null && uso.puestas >= uso.maximo!) return false;
    final relleno = defaultOptionFor(owner, group);
    return relleno != null && canAdd(owner, relleno);
  }

  /// De qué miniatura se quita una al pulsar el «−», o `null` si no se puede quitar ninguna.
  ///
  /// Del montón más grande y no del primero: quitando del primero se llevaría por delante al
  /// sargento, o el arma especial que el jugador acaba de elegir.
  ///
  /// Y respetando el suelo de **cada opción**, no solo el del grupo. El dataset escribe algunos
  /// mínimos en la propia miniatura —«Spindle Drone: mínimo 4»— y el grupo no dice nada; mirando
  /// solo el grupo, el «−» se dejaba pulsar y la unidad quedaba ilegal sin que el jugador hubiera
  /// elegido nada raro. Pasaba en **134 grupos**.
  Selection? shrinkTarget(Selection owner, OptionGroup group) {
    final uso = groupUsage(owner, group);
    if (uso.minimo != null && uso.puestas <= uso.minimo!) return null;
    final delGrupo = optionsFor(owner)
        .where((o) => modelGroupOf(owner, o)?.id == group.id)
        .where((o) => owner.cuantasDe(o) > 0)
        .where((o) => canRemove(owner, o))
        .toList();
    // Se quita primero del relleno: es la miniatura sin nada especial, y quitar antes la que lleva
    // el plasma sería deshacer una elección del jugador para hacer sitio.
    final relleno = delGrupo.where((o) => isFiller(owner, o)).firstOrNull;
    if (relleno != null) return relleno;
    delGrupo.sort((a, b) => owner.cuantasDe(b).compareTo(owner.cuantasDe(a)));
    return delGrupo.firstOrNull;
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
    final puestas = owner.cuantasDe(option);

    final desde = owner.puestaDe(option) ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);

    for (final constraint in option.constraints) {
      if (constraint.field != 'selections' || !constraint.isMax) continue;
      if (!_topeDeLaUnidad(owner, constraint.scope)) continue;
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

  /// La opción con la que crece un grupo: la de serie, y si no la básica.
  ///
  /// Es la que pone el botón «+» de un contador de miniaturas: al subir una escuadra de cinco a
  /// seis, la que entra es un soldado raso, no el arma especial ni el sargento. Quién es el raso lo
  /// dice el dataset sin decirlo: es el único cuyo techo llega al tamaño del grupo.
  Selection? defaultOptionFor(Selection owner, OptionGroup group) {
    final delGrupo = optionsFor(owner).where((o) => o.groupId == group.id).toList();
    if (delGrupo.isEmpty) return null;
    if (group.defaultId != null) {
      final marcada =
          delGrupo.where((o) => o.entryId == group.defaultId).firstOrNull;
      if (marcada != null) return marcada;
    }
    final uso = groupUsage(owner, group);
    final basica = _basicaDe(delGrupo, uso.maximo ?? uso.minimo ?? 1);
    if (basica != null) return basica;
    // Y si tampoco destaca ninguna, la primera en la que quepa una más: así el «+» no se queda
    // muerto cuando la que encabeza el grupo es el sargento y ya está puesto.
    return delGrupo.where((o) => canAdd(owner, o)).firstOrNull ?? delGrupo.first;
  }

  /// Si un grupo es el que decide **cuántas miniaturas** tiene la unidad.
  ///
  /// Lo es cuando todo lo que ofrece son miniaturas. Es la diferencia entre las dos formas que
  /// tiene una hoja de datos de dejarte elegir: una miniatura suelta —el Defiler— elige entre
  /// varias armas, y una escuadra elige **a cuántas de sus miniaturas** les cambia el arma.
  bool isModelGroup(Selection owner, OptionGroup group) {
    // Con memoria: esto lo pregunta la interfaz una vez por fila y resolver las opciones de una
    // unidad entera para contestarlo dejaba la pantalla colgada. La respuesta no depende de lo que
    // haya puesto —depende de qué **ofrece** el grupo—, así que vale para toda la partida.
    final clave = '${owner.entryId}|${group.id}';
    final recordado = _gruposDeMiniaturas[clave];
    if (recordado != null) return recordado;
    final suyas = optionsFor(owner).where((o) => o.groupId == group.id).toList();
    return _gruposDeMiniaturas[clave] =
        suyas.isNotEmpty && suyas.every((o) => o.type == 'model');
  }

  final Map<String, bool> _gruposDeMiniaturas = {};

  /// El grupo de miniaturas del que depende una opción: el suyo, o el que lo contiene.
  ///
  /// Las armas especiales cuelgan de un subgrupo con su propio techo —«Special weapons, máximo
  /// 2»— pero las miniaturas que las llevan salen del mismo montón que las demás. Sin subir al
  /// grupo de fuera no se sabe a quién se le quita el bólter.
  OptionGroup? modelGroupOf(Selection owner, Selection option) {
    final cadena = <OptionGroup>[];
    var grupo = owner.groups.where((g) => g.id == option.groupId).firstOrNull;
    while (grupo != null) {
      if (isModelGroup(owner, grupo)) cadena.add(grupo);
      grupo = owner.groups.where((g) => g.id == grupo!.parentId).firstOrNull;
    }
    if (cadena.isEmpty) return null;
    // El de fuera primero: es donde está el montón de miniaturas. «Special weapons» también es un
    // grupo de miniaturas, pero las que llevan el plasma salen del mismo sitio que las demás, así
    // que quedándose en él no habría a quién quitarle el bólter.
    //
    // «Donde está el montón» se mira en el árbol y no resolviendo opciones: esto se pregunta una
    // vez por fila y por miniatura puesta, y resolverlas cada vez colgaba la pantalla.
    for (final candidato in cadena.reversed) {
      if (owner.children.any((c) => c.groupId == candidato.id && c.count > 0)) {
        return candidato;
      }
    }
    return cadena.last;
  }

  /// Si esta opción es el relleno de su escuadra: la miniatura sin nada especial.
  bool isFiller(Selection owner, Selection option) {
    final grupo = modelGroupOf(owner, option);
    if (grupo == null) return false;
    return defaultOptionFor(owner, grupo)?.entryId == option.entryId;
  }

  /// Si se le puede cambiar el arma a una miniatura más.
  ///
  /// Cambiar un arma **no hace crecer la escuadra**: le quita el bólter a una de las que ya hay.
  /// Contarlo como una miniatura más era lo que dejaba la unidad bloqueada al llegar al máximo:
  /// con nueve Plague Marines no se podía poner ni un plasma, porque el hueco ya estaba ocupado
  /// por el propio marine al que había que quitárselo.
  ///
  /// Lo que sí manda es el techo del arma —«hasta 2 lanzaplagas»— y el de su subgrupo, que es
  /// donde el dataset escribe «por cada 5 miniaturas».
  bool canAssign(Selection owner, Selection option) {
    final grupo = modelGroupOf(owner, option);
    if (grupo == null) return false;
    final relleno = defaultOptionFor(owner, grupo);
    if (relleno == null || relleno.entryId == option.entryId) return false;
    if (owner.cuantasDe(relleno) < 1) return false;
    // Y sin bajar al relleno de su propio suelo: el Spectrus Kill Team exige cinco Infiltrators, y
    // cambiarle el arma a uno los dejaba en cuatro y la unidad ilegal. Ahí primero se crece la
    // escuadra y luego se cambia.
    if (!canRemove(owner, relleno)) return false;

    final puestas = owner.cuantasDe(option);
    final tope = effectiveMaxOf(owner, option);
    if (tope != null && puestas >= tope) return false;

    // Y lo que quede de la frase que la nombra, si nombra varias armas: «una de las siguientes»
    // es una miniatura eligiendo entre tres, no tres armas.
    for (final regla in reglasDeTopeDe(owner)) {
      if (regla.armas.length < 2) continue;
      if (!regla.hablaDe(option.name)) continue;
      if (librePorLaRegla(owner, regla) <= 0) return false;
    }

    // Y el techo del subgrupo, si sale de uno: «Special weapons, máximo 2».
    if (option.groupId != null && option.groupId != grupo.id) {
      final suyo = owner.groups.where((g) => g.id == option.groupId).firstOrNull;
      if (suyo != null) {
        final uso = groupUsage(owner, suyo);
        if (uso.maximo != null && uso.puestas >= uso.maximo!) return false;
      }
    }
    return true;
  }

  /// Le cambia el arma a una miniatura: una menos de relleno, una más de esta.
  ///
  /// Y la que entra llega con lo suyo puesto. Hay miniaturas que no son un arma sino una **rama**:
  /// el «Terminator w/ Heavy Weapon» no dice cuál, lo pregunta —assault cannon, heavy flamer o
  /// cyclone— y entra con ese hueco vacío y la unidad ilegal. Se rellena igual que al añadir la
  /// unidad, así que entra con algo puesto y se cambia de un toque.
  void assign(Selection owner, Selection option) {
    if (!canAssign(owner, option)) return;
    final grupo = modelGroupOf(owner, option)!;
    final relleno = defaultOptionFor(owner, grupo)!;
    _quitarUna(owner, relleno);
    // Dos armas pesadas son **dos miniaturas**, y cada una elige la suya. Si lo que se pone
    // pregunta algo —el «Terminator w/ Heavy Weapon» no dice cuál: assault cannon, heavy flamer o
    // cyclone— se mete una selección aparte por cada una, no un contador con un «×2». Con el
    // contador, la elección era una sola y valía para las dos, que es justo lo contrario de lo que
    // dice la hoja.
    final puesta = owner.puestaDe(option);
    if (puesta != null && !pideEleccion(puesta)) {
      puesta.count++;
    } else {
      owner.addChild(option);
      completeMinimums(option);
    }

    // Hay cosas que ocupan más de un hueco, y el dataset lo dice bajando el techo del grupo: un
    // Heavy Weapons Team son dos soldados, así que al ponerlo la escuadra pasa de admitir nueve a
    // admitir ocho. Se le quita al relleno lo que haga falta para que vuelva a caber; quitar de
    // más es lo que evita dejar la unidad ilegal por una cuenta que el jugador no ha hecho.
    for (var intento = 0; intento < 10; intento++) {
      final uso = groupUsage(owner, grupo);
      if (uso.maximo == null || uso.puestas <= uso.maximo!) break;
      if (owner.cuantasDe(relleno) < 1) break;
      _quitarUna(owner, relleno);
    }
  }

  /// Si esta miniatura, una vez puesta, **pregunta** algo: con qué arma va.
  ///
  /// Es lo que decide si dos de lo mismo son un contador —«2 × Blight launcher», que son dos
  /// miniaturas idénticas— o dos cuadros separados —«2 × Terminator w/ Heavy Weapon», donde una
  /// puede llevar cyclone y la otra assault cannon—.
  bool pideEleccion(Selection puesta) {
    final cacheado = _pregunta[puesta.entryId];
    if (cacheado != null) return cacheado;
    final pide = puesta.groups.isNotEmpty && optionsFor(puesta).isNotEmpty;
    return _pregunta[puesta.entryId] = pide;
  }

  final Map<String, bool> _pregunta = {};

  /// Cada una de las miniaturas puestas de esa opción, por separado.
  ///
  /// Normalmente es una sola con su contador; cuando la opción pregunta con qué arma va, son
  /// varias, y cada una lleva su respuesta dentro.
  List<Selection> instanciasDe(Selection owner, Selection option) => owner.children
      .where((c) => c.entryId == option.entryId && c.groupId == option.groupId)
      .toList();

  /// Le devuelve el arma de serie a **esa** miniatura, no a una cualquiera de las iguales.
  void unassignInstance(Selection owner, Selection instancia) {
    final grupo = modelGroupOf(owner, instancia);
    if (grupo == null) return;
    final relleno = defaultOptionFor(owner, grupo);
    if (relleno == null || relleno.entryId == instancia.entryId) return;
    if (instancia.count > 1) {
      instancia.count--;
    } else {
      owner.children.remove(instancia);
    }
    final puesta = owner.puestaDe(relleno);
    if (puesta != null) {
      puesta.count++;
    } else {
      owner.addChild(relleno);
    }
  }

  /// La opción «Warlord» de una unidad, si la ofrece.
  ///
  /// El dataset la escribe como una mejora suelta más, y pintada como tal salía con un contador de
  /// menos y más. No es una cantidad: el ejército tiene **un** Warlord y esto es el interruptor.
  Selection? warlordOptionOf(Selection unit) =>
      optionsFor(unit).where((o) => o.name == 'Warlord').firstOrNull;

  bool isWarlord(Selection unit) =>
      unit.children.any((c) => c.name == 'Warlord' && c.count > 0);

  /// Si esta unidad tiene que ser el Warlord y no se puede elegir otra cosa.
  bool mustBeWarlord(Selection unit) {
    final entrada = unitEntryOf(unit);
    return entrada != null && faction.dataset.debeSerWarlord(entrada);
  }

  /// Pone el Warlord aquí y se lo quita a quien lo tuviera: solo puede haber uno.
  void setWarlord(Selection unit) {
    for (final otra in units) {
      if (identical(otra, unit)) continue;
      otra.children.removeWhere((c) => c.name == 'Warlord');
    }
    if (isWarlord(unit)) return;
    final opcion = warlordOptionOf(unit);
    if (opcion != null) unit.addChild(opcion);
  }

  void clearWarlord(Selection unit) {
    if (mustBeWarlord(unit)) return;
    unit.children.removeWhere((c) => c.name == 'Warlord');
  }

  /// El Warlord de la lista, si ya hay uno.
  Selection? get warlord => units.where(isWarlord).firstOrNull;

  /// Deja el Warlord donde manda la regla: si hay un Supreme Commander en la lista, es él.
  ///
  /// «Si esta miniatura está en tu ejército, debe ser tu WARLORD» no admite otra respuesta, así
  /// que la app la da sola en vez de dejar una casilla que solo se puede marcar de una manera.
  void ajustarWarlord() {
    final obligado = units.where(mustBeWarlord).firstOrNull;
    if (obligado != null) {
      setWarlord(obligado);
      return;
    }
    // Y nunca dos: si dos unidades acabaron con la marca, se queda la primera.
    var visto = false;
    for (final unidad in units) {
      if (!isWarlord(unidad)) continue;
      if (visto) {
        unidad.children.removeWhere((c) => c.name == 'Warlord');
      } else {
        visto = true;
      }
    }
  }

  /// Rellena lo que una selección recién puesta exige y no trae.
  ///
  /// Es lo mismo que se hace al meter una unidad en la lista, pero para una pieza suelta: una
  /// opción que a su vez pregunta algo entra con el hueco abierto, y ese hueco deja la unidad
  /// ilegal por algo que el jugador no ha decidido.
  void completeMinimums(Selection selection) {
    _prune(selection);
    _completarMinimos(selection);
  }

  /// Le devuelve el arma de serie: una menos de esta, una más de relleno.
  void unassign(Selection owner, Selection option) {
    final grupo = modelGroupOf(owner, option);
    if (grupo == null) return;
    if (owner.cuantasDe(option) < 1) return;
    final relleno = defaultOptionFor(owner, grupo);
    if (relleno == null || relleno.entryId == option.entryId) return;
    _quitarUna(owner, option);
    final puesta = owner.puestaDe(relleno);
    if (puesta != null) {
      puesta.count++;
    } else {
      owner.addChild(relleno);
    }
  }

  void _quitarUna(Selection owner, Selection option) {
    // La última, que es la que se acaba de poner: con varias miniaturas separadas, quitar la
    // primera se llevaría por delante una elección vieja que el jugador no ha tocado.
    final puesta = owner.children
        .where((c) => c.entryId == option.entryId && c.groupId == option.groupId)
        .lastOrNull;
    if (puesta == null) return;
    if (puesta.count > 1) {
      puesta.count--;
    } else {
      owner.children.remove(puesta);
    }
  }

  /// El techo efectivo de una opción, con los modifiers que lo cambian ya aplicados.
  ///
  /// Es el número que hay que enseñar: el dataset escribe «hasta 1 arma pesada» y luego un
  /// modifier lo sube a 2 cuando la escuadra pasa de cinco, que es como dice «una por cada cinco
  /// miniaturas». El declarado, a secas, miente en cuanto la escuadra crece.
  int? effectiveMaxOf(Selection owner, Selection option) {
    final desde = owner.puestaDe(option) ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);
    int? tope;
    for (final constraint in option.constraints) {
      if (constraint.field != 'selections' || !constraint.isMax) continue;
      if (!_topeDeLaUnidad(owner, constraint.scope)) continue;
      final limit = _effectiveLimit(constraint, desde, option.modifiers);
      if (limit == null || limit < 0) continue;
      if (tope == null || limit < tope) tope = limit;
    }

    // Y el que dice la frase impresa, que manda cuando es más bajo: BSData deja muchos techos
    // puestos al valor de la escuadra llena y con media escuadra decía que cabía el doble.
    final impreso = topeImpresoDe(owner, option);
    if (impreso != null && (tope == null || impreso < tope)) tope = impreso;
    return tope;
  }

  /// El techo que dice la **frase impresa** de la hoja, con la escuadra que hay ahora mismo.
  ///
  /// Es lo que el dataset no siempre sabe decir. BSData deja el techo del blight launcher en 2
  /// —el de una escuadra de diez— y mete el «uno por cada cinco» en un modifier de tipo `error`,
  /// que solo sirve para pintar un aviso. Con cinco Plague Marines la app dejaba poner dos blight
  /// launchers y dos plague spewers: cuatro armas especiales en una escuadra de cinco.
  ///
  /// El relleno nunca pasa por aquí. La frase habla de **reemplazos** —«1 Terminator's storm
  /// bolter can be replaced with…»— y nombra de paso armas que la miniatura de serie ya lleva; sin
  /// esta salvaguarda, «storm bolter» recortaría la escuadra entera a una miniatura.
  int? topeImpresoDe(Selection owner, Selection option) {
    final reglas = reglasDeTopeDe(owner);
    if (reglas.isEmpty) return null;
    if (isFiller(owner, option)) return null;
    final miniaturas = _miniaturasDe(owner);
    if (miniaturas == null) return null;
    int? tope;
    for (final regla in reglas) {
      if (!regla.hablaDe(option.name)) continue;
      final suyo = regla.enUnidadDe(miniaturas);
      if (tope == null || suyo < tope) tope = suyo;
    }
    // Nunca a cero. La frase dice cómo **escala** el tope, no si el arma existe; eso lo dice el
    // dataset. Y hay escuadras cuyo mínimo en BSData queda por debajo del de la hoja —el Blightlord
    // arranca en tres donde la hoja dice cinco—, así que un cero aquí sería esconder todas las
    // opciones de la unidad por una cuenta que no es del jugador.
    return tope == null ? null : (tope < 1 ? 1 : tope);
  }

  /// Cuántas quedan por repartir de una regla que nombra varias armas.
  ///
  /// «1 Plague Marine's plague boltgun can be replaced with one of the following: 1 meltagun ; 1
  /// plague belcher ; 1 plasma gun» es **una** miniatura eligiendo entre tres, no una por arma.
  /// Contando cada arma por su cuenta salían tres armas especiales donde cabe una.
  int librePorLaRegla(Selection owner, TopePorMiniaturas regla) {
    final miniaturas = _miniaturasDe(owner);
    if (miniaturas == null) return 0;
    final relleno = _rellenoDe(owner);
    var puestas = 0;
    for (final hijo in owner.children) {
      if (relleno != null && hijo.entryId == relleno.entryId) continue;
      if (regla.hablaDe(hijo.name)) puestas += hijo.count;
    }
    return regla.enUnidadDe(miniaturas) - puestas;
  }

  /// Las reglas impresas de la unidad a la que pertenece [selection].
  List<TopePorMiniaturas> reglasDeTopeDe(Selection selection) {
    final entrada = unitEntryOf(selection);
    if (entrada == null) return const [];
    final cacheada = _reglas[entrada.id];
    if (cacheada != null) return cacheada;
    final leidas = topesDe(faction.dataset.wargearNotesOf(entrada));
    entrada.topesImpresos = leidas;
    return _reglas[entrada.id] = leidas;
  }

  final Map<String, List<TopePorMiniaturas>> _reglas = {};

  /// La entrada de catálogo de la unidad de la que cuelga [selection].
  UnitEntry? unitEntryOf(Selection selection) {
    var raiz = selection;
    while (raiz.parent != null) {
      raiz = raiz.parent!;
    }
    if (_porId.isEmpty) {
      for (final u in faction.units) {
        _porId[u.id] = u;
      }
    }
    return _porId[raiz.entryId];
  }

  final Map<String, UnitEntry> _porId = {};

  /// Las miniaturas de la unidad entera, que es de lo que habla la frase.
  ///
  /// «For every 10 models **in this unit**» son todas: los nueve Boyz y el Nob, aunque el dataset
  /// los tenga en dos grupos y el Nob se dimensione aparte. Contando solo el grupo principal, una
  /// escuadra de diez Boyz daba nueve y la frase se quedaba en cero armas.
  int? _miniaturasDe(Selection owner) {
    var cuantas = 0;
    for (final hijo in owner.children) {
      if (hijo.type == 'model') cuantas += hijo.count;
    }
    return cuantas > 0 ? cuantas : null;
  }

  Selection? _rellenoDe(Selection owner) {
    final grupo = mainModelGroup(owner);
    return grupo == null ? null : defaultOptionFor(owner, grupo);
  }

  /// Si un tope escrito con ese ámbito habla de esta unidad.
  ///
  /// El dataset no escribe todos los techos contra el padre. El «Rough Rider w/ Goad lance» lleva
  /// el suyo contra **el id de su grupo**, y otras armas lo escriben contra `unit`, que es la
  /// unidad entera. Mirando solo `parent` y `self` esos techos no existían, y la app dejaba poner
  /// diez lanzas donde la hoja pone «una por cada cinco miniaturas».
  ///
  /// Lo que queda fuera es `roster` y `force`: eso no es el techo de esta unidad sino el del
  /// ejército —«dos en toda la lista»—, y aplicarlo aquí sería recortar una unidad por lo que
  /// lleven las demás.
  bool _topeDeLaUnidad(Selection owner, String? scope) {
    if (scope == null) return false;
    if (scope == 'parent' || scope == 'self' || scope == 'unit') return true;
    if (owner.groups.any((g) => g.id == scope)) return true;
    // O el id de la propia unidad, que es como el dataset escribe «dos en esta unidad»: el techo
    // del Goad lance apunta a la entrada «Attilan Rough Riders», no a `parent`.
    for (Selection? nodo = owner; nodo != null; nodo = nodo.parent) {
      if (nodo.entryId == scope) return true;
    }
    return false;
  }

  /// Si se puede quitar una de esa opción de debajo de [owner].
  ///
  /// El dataset escribe equipo fijo como un mínimo en la propia opción: las Shearing claws del
  /// Defiler son `min 1, max 1`, o sea que las lleva y punto, no es una elección. Pintar ahí un
  /// contador con su botón de quitar es ofrecer algo que no existe: se baja a cero, la unidad se
  /// queda ilegal y el aviso que sale no dice cómo arreglarlo. Lo mismo con las miniaturas que
  /// vienen de serie en una escuadra.
  ///
  /// Un grupo que solo deja elegir una cosa no pasa por aquí: ahí lo que hay es un botón de radio
  /// y quitar significa elegir otra.
  bool canRemove(Selection owner, Selection option, {bool hayAlternativas = false}) {
    final puestas = owner.cuantasDe(option);
    if (puestas <= 0) return false;
    // Con alternativas en el grupo, el mínimo que manda es el del grupo y no el de la opción:
    // quitar esta para poner otra es legal, y es justo para lo que está el grupo.
    if (hayAlternativas) return true;

    final desde = owner.puestaDe(option) ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);

    for (final constraint in option.constraints) {
      if (constraint.field != 'selections' || constraint.isMax) continue;
      if (constraint.scope != 'parent' && constraint.scope != 'self') continue;
      final limit = _effectiveLimit(constraint, desde, option.modifiers);
      if (limit != null && limit > 0 && puestas <= limit) return false;
    }
    return true;
  }

  /// Si esa opción es equipo fijo: el dataset la exige, no deja poner más de una y **no hay otra
  /// que ponerle en su lugar**.
  ///
  /// Es lo que separa «esto lo lleva la miniatura» de «esto lo eliges tú», y no hay bandera que lo
  /// diga: se deduce de que el mínimo y el máximo efectivos coincidan.
  ///
  /// Lo tercero es lo que faltaba y no es un detalle: mirando solo el mínimo y el máximo se
  /// bloqueaban **15.273 opciones de 17.505** que sí eran una elección. Un arma con `min 1, max 1`
  /// dentro de un grupo que ofrece otras tres no es equipo fijo: es la que está puesta ahora, y el
  /// grupo existe justo para cambiarla. Fijo de verdad es lo que no tiene alternativa: las
  /// Shearing claws del Defiler, o las dos armas de Asurmen, que no cuelgan de ningún grupo.
  ///
  /// Quien sabe si hay alternativas es quien tiene delante la lista de opciones del grupo, así que
  /// se le pregunta en vez de recalcularla aquí para cada fila.
  bool isFixed(Selection owner, Selection option, {bool hayAlternativas = false}) {
    if (hayAlternativas) return false;
    return _minimoIgualAlMaximo(owner, option);
  }

  bool _minimoIgualAlMaximo(Selection owner, Selection option) {
    final desde = owner.puestaDe(option) ??
        (Selection(entryId: '', name: '', type: '', baseCosts: const {})..parent = owner);
    int? minimo, maximo;
    for (final constraint in option.constraints) {
      if (constraint.field != 'selections') continue;
      if (constraint.scope != 'parent' && constraint.scope != 'self') continue;
      final limit = _effectiveLimit(constraint, desde, option.modifiers);
      if (limit == null || limit < 0) continue;
      if (constraint.isMax) {
        maximo = maximo == null || limit < maximo ? limit : maximo;
      } else {
        minimo = minimo == null || limit > minimo ? limit : minimo;
      }
    }
    return minimo != null && minimo > 0 && minimo == maximo;
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
