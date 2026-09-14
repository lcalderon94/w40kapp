import 'dart:convert';
import 'dart:io';

import 'detachment.dart';
import 'model.dart';
import 'modifiers.dart';
import 'roster.dart';

/// El dataset de BattleScribe ya traducido, cargado y resuelto.
///
/// Los 46 ficheros no son independientes: se referencian entre ellos por identificador, así que
/// hay que indexarlos todos juntos antes de poder resolver nada. Una facción cargada por su cuenta
/// no puede listar sus unidades.
class Dataset {
  Dataset._(this._nodesById, this._roots);

  final Map<String, Map<String, dynamic>> _nodesById;
  final List<Map<String, dynamic>> _roots;

  /// Carga los ficheros JSON de [directory]. Espera el dataset completo, no un fichero suelto.
  static Future<Dataset> load(Directory directory) async {
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw ArgumentError('El directorio no contiene ficheros del dataset: ${directory.path}');
    }
    return fromJson([for (final file in files) await file.readAsString()]);
  }

  /// Igual, pero a partir del texto de los ficheros en vez de del disco.
  ///
  /// Es la puerta que usa la app, donde el dataset viene empaquetado en los assets y no hay
  /// sistema de ficheros que recorrer. Espera el dataset completo: los ficheros se referencian
  /// entre ellos, así que con un subconjunto no se resuelve nada.
  static Dataset fromJson(Iterable<String> contents) {
    final nodesById = <String, Map<String, dynamic>>{};
    final roots = <Map<String, dynamic>>[];
    for (final content in contents) {
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      roots.add(decoded.values.first as Map<String, dynamic>);
      _index(decoded, nodesById);
    }
    if (roots.isEmpty) throw ArgumentError('El dataset está vacío');
    return Dataset._(nodesById, roots);
  }

  static void _index(Object? node, Map<String, Map<String, dynamic>> into) {
    if (node is Map<String, dynamic>) {
      final id = node['id'];
      if (id is String) into.putIfAbsent(id, () => node);
      for (final value in node.values) {
        _index(value, into);
      }
    } else if (node is List) {
      for (final value in node) {
        _index(value, into);
      }
    }
  }

  /// El nodo con ese identificador, de cualquiera de los ficheros.
  Map<String, dynamic>? node(String id) => _nodesById[id];

  int get nodeCount => _nodesById.length;

  /// Las facciones jugables. Quedan fuera las librerías, que solo aportan contenido compartido.
  List<Faction> get factions => _roots
      .where((r) => r['type'] == 'catalogue' && r['library'] != true)
      .map((r) => Faction(this, r))
      .toList();

  Faction factionNamed(String name) =>
      factions.firstWhere((f) => f.name == name, orElse: () => throw ArgumentError('No existe la facción $name'));

  /// Resuelve las unidades seleccionables de una facción.
  ///
  /// Son sus entradas raíz más las de los catálogos que enlaza con `importRootEntries`. Ese
  /// segundo grupo es lo que da contenido a los capítulos de Space Marines, que apenas declaran
  /// unidades propias.
  List<UnitEntry> unitsOf(Faction faction) {
    final units = <UnitEntry>[];
    final seen = <String>{};
    for (final link in _rootLinks(faction.node)) {
      final target = node(link['targetId'] as String? ?? '');
      if (target == null) continue;
      if (target['type'] != 'unit' && target['type'] != 'model') continue;
      if (!seen.add(target['id'] as String? ?? '')) continue;
      units.add(_toUnit(target));
    }
    return units;
  }

  /// Las entradas raíz de una facción: las suyas más las que hereda por `importRootEntries`.
  List<Map<String, dynamic>> _rootLinks(Map<String, dynamic> catalogue, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    if (!visited.add(catalogue['id'] as String? ?? '')) return const [];
    final links = <Map<String, dynamic>>[
      for (final raw in (catalogue['entryLinks'] as List? ?? const [])) raw as Map<String, dynamic>,
    ];
    for (final raw in (catalogue['catalogueLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      if (link['importRootEntries'] != true) continue;
      final target = node(link['targetId'] as String? ?? '');
      if (target != null) links.addAll(_rootLinks(target, visited));
    }
    return links;
  }

  /// Los detachments de una facción, con su regla ya traducida.
  ///
  /// Cuelgan de la entrada de configuración, en un grupo que unas facciones llevan incrustado y
  /// otras enlazan a un grupo compartido, y que el dataset llama `Detachment` o `Detachments`.
  ///
  /// Un mismo grupo puede servir a varias facciones y a varios modos de juego, y entonces no todo
  /// lo que contiene es de todos: se descarta lo que el propio dataset esconde. Ver
  /// [_hiddenForCatalogue] y [_isBoardingActions].
  ///
  /// Con [boardingActions] se piden los de ese modo en vez de los de una partida normal.
  List<Detachment> detachmentsOf(Faction faction, {bool boardingActions = false}) {
    final catalogueId = faction.node['id'] as String? ?? '';
    final detachments = <Detachment>[];
    final seen = <String>{};
    for (final link in _rootLinks(faction.node)) {
      final entry = node(link['targetId'] as String? ?? '');
      if (entry == null || !_isConfiguration(entry)) continue;
      for (final group in _groupsOf(entry)) {
        if (!_isDetachmentGroup(group)) continue;
        for (final option in _childEntries(group)) {
          if (_hiddenForCatalogue(option, catalogueId)) continue;
          if (_isBoardingActions(option) != boardingActions) continue;
          if (!seen.add(option['id'] as String? ?? '')) continue;
          final rule = (option['rules'] as List? ?? const []).isEmpty
              ? null
              : (option['rules'] as List).first as Map<String, dynamic>;
          detachments.add(Detachment(
            id: option['id'] as String? ?? '',
            name: option['name'] as String? ?? '',
            ruleName: rule?['name'] as String?,
            rule: rule?['description'] as String?,
            points: _points(option) ?? 0,
            detachmentPoints: _costsOf(option)[detachmentPointsCostTypeId] ?? 0,
          ));
        }
      }
    }
    return detachments;
  }

  /// Las reglas del reglamento básico, ya traducidas y ordenadas por nombre.
  ///
  /// Viven en el fichero del sistema de juego, no en los catálogos, porque no son de ninguna
  /// facción: son las palabras clave que el jugador se encuentra entre corchetes y tiene que ir a
  /// buscar. Tenerlas dentro es lo que permite explicarlas sin salir de la app.
  late final List<Rule> coreRules = () {
    final rules = <Rule>[];
    for (final root in _roots) {
      if (root['type'] != 'gameSystem') continue;
      for (final raw in (root['sharedRules'] as List? ?? const [])) {
        final rule = raw as Map<String, dynamic>;
        final description = rule['description'] as String?;
        if (description == null || description.isEmpty) continue;
        rules.add(Rule(
          id: rule['id'] as String? ?? '',
          name: rule['name'] as String? ?? '',
          description: description,
        ));
      }
    }
    return rules..sort((a, b) => a.name.compareTo(b.name));
  }();

  /// Los tipos de fuerza que declara el sistema de juego.
  ///
  /// Son cuatro y una lista es de uno solo, así que saber cuál es contesta por sí mismo las
  /// condiciones `instanceOf` que preguntan por ellos, que si no habría que dejar sin evaluar.
  late final List<Force> forces = [
    for (final root in _roots) ..._forcesIn(root),
  ];

  /// Las fuerzas de un nodo y las que anidan dentro: Crusade Army cuelga de Crusade Force.
  Iterable<Force> _forcesIn(Map<String, dynamic> node_) sync* {
    for (final raw in (node_['forceEntries'] as List? ?? const [])) {
      final entry = raw as Map<String, dynamic>;
      yield Force(
        id: entry['id'] as String? ?? '',
        name: entry['name'] as String? ?? '',
        node: entry,
      );
      yield* _forcesIn(entry);
    }
  }

  /// La fuerza de una partida normal, que es la que se asume mientras no se diga otra cosa.
  late final Force standardForce = forces.firstWhere((f) => f.name == 'Army Roster',
      orElse: () => Force(id: '', name: 'Army Roster', node: const {}));

  /// Los tamaños de partida que ofrece el sistema de juego, con su límite de puntos.
  ///
  /// El límite no se saca del nombre sino del propio dataset: la entrada «Points limit» lleva un
  /// modifier de `defaultAmount` por tamaño, y la condición de cada uno dice a cuál corresponde.
  late final List<BattleSize> battleSizes = _readBattleSizes();

  List<BattleSize> _readBattleSizes() {
    final entry = _battleSizeEntry;
    if (entry == null) return const [];

    final limits = <String, int>{};
    for (final node_ in _descendants(entry)) {
      for (final modifier in Modifier.allOf(node_)) {
        if (modifier.field != 'defaultAmount') continue;
        final limit = int.tryParse('${modifier.value}');
        if (limit == null) continue;
        for (final condition in modifier.conditions) {
          limits[condition.childId] = limit;
        }
      }
    }

    return [
      for (final group in _groupsOf(entry))
        if (group['name'] == 'Battle Size')
          for (final option in _childEntries(group))
            BattleSize(
              id: option['id'] as String? ?? '',
              name: option['name'] as String? ?? '',
              pointsLimit: limits[option['id']] ?? 0,
            ),
    ];
  }

  Map<String, dynamic>? get _battleSizeEntry {
    for (final root in _roots) {
      for (final raw in (root['sharedSelectionEntries'] as List? ?? const [])) {
        final entry = raw as Map<String, dynamic>;
        if (entry['name'] == 'Battle Size') return entry;
      }
    }
    return null;
  }

  Iterable<Map<String, dynamic>> _descendants(Object? node_) sync* {
    if (node_ is Map<String, dynamic>) {
      yield node_;
      for (final value in node_.values) {
        yield* _descendants(value);
      }
    } else if (node_ is List) {
      for (final value in node_) {
        yield* _descendants(value);
      }
    }
  }

  /// Las mejoras que habilita un detachment, con su texto ya traducido.
  ///
  /// Una mejora es una opción con coste en puntos que el dataset esconde salvo que se haya elegido
  /// ese detachment. No vale reconocerlas por el coste del tipo Enhancements ni por el nombre de su
  /// grupo: hay facciones que no usan ese coste y otras que llaman al grupo de otra manera, así que
  /// lo que las identifica es a qué detachment están atadas.
  ///
  /// El gate puede estar en la propia mejora o en cualquiera de los nodos que la contienen, y las
  /// mejoras pueden vivir en un catálogo enlazado, no solo en el de la facción.
  ///
  /// Se queda corto antes que inventarse nada: si devuelve una mejora, es de ese detachment. Ver
  /// [enhancementCoverage].
  List<Enhancement> enhancementsOf(Faction faction, {required String detachmentId}) {
    final enhancements = <Enhancement>[];
    final seen = <String>{};
    for (final catalogue in _linkedCatalogues(faction.node)) {
      _collectEnhancements(catalogue, const {}, (entry, gates) {
        if (!gates.contains(detachmentId)) return;
        if (!seen.add(entry['id'] as String? ?? '')) return;
        final profile = (entry['profiles'] as List? ?? const []).isEmpty
            ? null
            : Profile.fromNode((entry['profiles'] as List).first as Map<String, dynamic>);
        enhancements.add(Enhancement(
          id: entry['id'] as String? ?? '',
          name: entry['name'] as String? ?? '',
          points: _points(entry) ?? 0,
          description: profile?.description,
        ));
      });
    }
    return enhancements;
  }

  /// Recorre un catálogo acumulando los detachments que nombra cada nivel al esconderse.
  ///
  /// El gate puede estar en la propia mejora o en el grupo que la contiene, así que se arrastra
  /// hacia abajo lo que declaran los nodos por los que se pasa.
  void _collectEnhancements(Object? node_, Set<String> inherited,
      void Function(Map<String, dynamic>, Set<String>) found) {
    if (node_ is Map<String, dynamic>) {
      final gates = {...inherited, ..._hiddenGates(node_)};
      if (_isEnhancement(node_)) found(node_, gates);
      for (final value in node_.values) {
        _collectEnhancements(value, gates, found);
      }
    } else if (node_ is List) {
      for (final value in node_) {
        _collectEnhancements(value, inherited, found);
      }
    }
  }

  static bool _isEnhancement(Map<String, dynamic> entry) =>
      entry['type'] == 'upgrade' &&
      (entry['name'] as String? ?? '').isNotEmpty &&
      (entry['costs'] as List? ?? const []).any((raw) =>
          (raw as Map<String, dynamic>)['typeId'] == pointsCostTypeId &&
          ((raw['value'] as num?) ?? 0) > 0);

  /// Los identificadores que un nodo nombra en las condiciones de sus modifiers `hidden`.
  Set<String> _hiddenGates(Map<String, dynamic> node_) {
    final gates = <String>{};
    for (final modifier in Modifier.allOf(node_)) {
      if (modifier.field != 'hidden') continue;
      for (final condition in modifier.allConditions) {
        gates.add(condition.childId);
      }
    }
    return gates;
  }

  /// Cuántos detachments de la facción tienen mejoras localizadas, y cuántos no.
  ///
  /// Sirve para saber de qué se puede fiar la interfaz antes de enseñar una lista vacía.
  ({int withEnhancements, int total}) enhancementCoverage(Faction faction) {
    final detachments = detachmentsOf(faction);
    final resolved = detachments
        .where((d) => enhancementsOf(faction, detachmentId: d.id).isNotEmpty)
        .length;
    return (withEnhancements: resolved, total: detachments.length);
  }

  /// La facción y todos los catálogos que enlaza, de donde salen sus opciones compartidas.
  List<Map<String, dynamic>> _linkedCatalogues(Map<String, dynamic> catalogue, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    if (!visited.add(catalogue['id'] as String? ?? '')) return const [];
    final catalogues = <Map<String, dynamic>>[catalogue];
    for (final raw in (catalogue['catalogueLinks'] as List? ?? const [])) {
      final target = node((raw as Map<String, dynamic>)['targetId'] as String? ?? '');
      if (target != null) catalogues.addAll(_linkedCatalogues(target, visited));
    }
    return catalogues;
  }

  static bool _isDetachmentGroup(Map<String, dynamic> group) {
    final name = group['name'];
    return name == 'Detachment' || name == 'Detachments';
  }

  /// El tipo de coste con el que 11ª gradúa los detachments y presupuesta el ejército.
  static const detachmentPointsCostTypeId = '82ae-1066-5107-6ae0';

  /// La categoría que marca una fuerza de Boarding Actions, el modo de juego a bordo de una nave.
  ///
  /// El identificador está fijo aquí porque lo está en el dataset, igual que el del coste en
  /// puntos. Hay un test que comprueba que sigue nombrando esa categoría, para que un cambio de
  /// upstream rompa en vez de dejar de filtrar sin avisar.
  static const boardingActionsCategoryId = '1d6e-2579-8e7f-1ed4';

  /// Si este detachment es de Boarding Actions y no de una partida normal.
  ///
  /// El dataset mete los dos en el mismo grupo y los reparte con un modifier de ámbito `force`:
  /// los normales se esconden **en** Boarding Actions (`instanceOf`) y los del modo se esconden
  /// **fuera** de él (`notInstanceOf`). Son los catorce que no llevan mejoras, así que sin separar
  /// unos de otros una lista normal ofrece detachments que en ella no se pueden jugar.
  static bool _isBoardingActions(Map<String, dynamic> entry) {
    for (final modifier in Modifier.allOf(entry)) {
      if (modifier.field != 'hidden' || modifier.type != 'set' || modifier.value != true) continue;
      for (final condition in modifier.conditions) {
        if (condition.scope != 'force') continue;
        if (condition.childId != boardingActionsCategoryId) continue;
        if (condition.type == 'notInstanceOf') return true;
      }
    }
    return false;
  }

  /// Si el dataset esconde esta opción cuando el catálogo principal es [catalogueId].
  ///
  /// Hay grupos de detachments que sirven a varias facciones a la vez: los de Aeldari y Drukhari
  /// son los mismos veinticuatro de la librería compartida, y los de los doce capítulos de Space
  /// Marines los cincuenta y ocho del codex común. Lo que reparte unos y otros es un modifier que
  /// los esconde según cuál sea el catálogo principal, y sin evaluarlo los Ultramarines ofrecerían
  /// el Inner Circle Task Force de los Dark Angels y los Aeldari saldrían a jugar con detachments
  /// Drukhari.
  ///
  /// Se miran solo las condiciones sueltas del modifier porque son las únicas que hay: ninguna de
  /// las 265 opciones de detachment del dataset mete estas condiciones en un grupo, así que cada
  /// una decide por sí sola y no hace falta interpretar ningún `and` ni `or`.
  static bool _hiddenForCatalogue(Map<String, dynamic> entry, String catalogueId) {
    for (final modifier in Modifier.allOf(entry)) {
      if (modifier.field != 'hidden' || modifier.type != 'set' || modifier.value != true) continue;
      for (final condition in modifier.conditions) {
        if (condition.scope != 'primary-catalogue') continue;
        final isThisCatalogue = condition.childId == catalogueId;
        if (condition.type == 'instanceOf' && isThisCatalogue) return true;
        if (condition.type == 'notInstanceOf' && !isThisCatalogue) return true;
      }
    }
    return false;
  }

  static bool _isConfiguration(Map<String, dynamic> entry) =>
      (entry['categoryLinks'] as List? ?? const []).any((raw) =>
          (raw as Map<String, dynamic>)['primary'] == true && raw['name'] == 'Configuration');

  /// Los grupos de opciones de un nodo, estén incrustados o lleguen por enlace.
  Iterable<Map<String, dynamic>> _groupsOf(Map<String, dynamic> node_) =>
      _groupLinks(node_).map((group) => group.group);

  /// Todos los grupos que cuelgan de un nodo, incluidos los que anidan otros grupos.
  ///
  /// El dataset los anida: «Heavy Weapons» no cuelga del tanque sino de su grupo «Wargear». Sin
  /// bajar, ni se despliegan sus mínimos obligatorios ni se pueden ofrecer sus opciones.
  Iterable<({Map<String, dynamic> group, Map<String, dynamic>? link})> _allGroupsOf(
      Map<String, dynamic> node_, [Set<String>? seen]) sync* {
    final visited = seen ?? <String>{};
    for (final entry in _groupLinks(node_)) {
      if (!visited.add(entry.group['id'] as String? ?? '')) continue;
      yield entry;
      yield* _allGroupsOf(entry.group, visited);
    }
  }

  /// Igual, pero conservando el enlace por el que se llega a cada grupo.
  ///
  /// Importa tanto como en las entradas: un grupo compartido se ajusta donde se usa, y el ajuste
  /// —«aquí solo un arma pesada, no dos»— vive en las restricciones del enlace, no en el grupo.
  Iterable<({Map<String, dynamic> group, Map<String, dynamic>? link})> _groupLinks(
      Map<String, dynamic> node_) sync* {
    for (final raw in (node_['selectionEntryGroups'] as List? ?? const [])) {
      yield (group: raw as Map<String, dynamic>, link: null);
    }
    for (final raw in (node_['entryLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      if (link['type'] != 'selectionEntryGroup') continue;
      final target = node(link['targetId'] as String? ?? '');
      if (target != null) yield (group: target, link: link);
    }
  }

  UnitEntry _toUnit(Map<String, dynamic> entry) {
    String? role;
    final keywords = <String>[];
    for (final raw in (entry['categoryLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      final name = link['name'] as String?;
      if (name == null) continue;
      keywords.add(name);
      if (link['primary'] == true) role = name;
    }

    return UnitEntry(
      id: entry['id'] as String? ?? '',
      name: entry['name'] as String? ?? '',
      type: entry['type'] as String? ?? '',
      role: role,
      keywords: keywords,
      points: _basePoints(entry),
      profiles: profilesOf(entry),
      constraints: [
        for (final raw in (entry['constraints'] as List? ?? const []))
          Constraint.fromNode(raw as Map<String, dynamic>),
      ],
    );
  }

  /// Puntos declarados en la entrada; si no los declara, los de la miniatura que cuelga de ella.
  ///
  /// Hay unidades que no se cuestan a sí mismas sino en su miniatura: el Myphitic Blight-hauler no
  /// tiene coste propio y sus 95 puntos están un nivel más abajo.
  int? _basePoints(Map<String, dynamic> entry) {
    final own = _points(entry);
    if (own != null) return own;
    for (final raw in (entry['selectionEntries'] as List? ?? const [])) {
      final child = raw as Map<String, dynamic>;
      if (child['type'] != 'model') continue;
      final points = _points(child);
      if (points != null) return points;
    }
    return null;
  }

  /// Todo lo que declara costar una entrada, por tipo de coste, quitando los ceros.
  static Map<String, int> _costsOf(Map<String, dynamic> entry) {
    final costs = <String, int>{};
    for (final raw in (entry['costs'] as List? ?? const [])) {
      final cost = raw as Map<String, dynamic>;
      final typeId = cost['typeId'] as String?;
      final value = cost['value'];
      if (typeId != null && value is num && value != 0) costs[typeId] = value.round();
    }
    return costs;
  }

  int? _points(Map<String, dynamic> node) {
    for (final raw in (node['costs'] as List? ?? const [])) {
      final cost = raw as Map<String, dynamic>;
      if (cost['typeId'] == pointsCostTypeId) {
        final value = cost['value'];
        if (value is num && value > 0) return value.round();
      }
    }
    return null;
  }

  /// Construye la selección de partida de una unidad: la unidad con los mínimos que exige.
  ///
  /// No basta con añadir la unidad suelta. Los Poxwalkers cuestan 65 puntos pero su grupo obliga a
  /// meter diez miniaturas, y hay unidades que dejan todo su coste en la miniatura, así que sin
  /// desplegar los mínimos el precio sale mal.
  Selection selectionFor(UnitEntry unit) {
    final entry = node(unit.id);
    if (entry == null) throw ArgumentError('No existe la entrada ${unit.id}');
    return _selectionFrom(entry, groupId: null, groupName: null, groupConstraints: const []);
  }

  /// Todo lo que el jugador puede añadir a una selección: las opciones de sus grupos y sus
  /// entradas hijas, cada una ya construida y lista para `addChild`.
  ///
  /// [selectionFor] solo despliega lo obligatorio, que es lo que hace falta para dar un precio.
  /// Esto es lo otro: lo que se elige. Las armas, el equipo y también las **mejoras**, que no son
  /// un caso aparte sino un grupo más de los que cuelgan de un personaje.
  ///
  /// Vienen con sus costes, sus restricciones y los ajustes de su enlace, así que validan y suman
  /// igual que si hubieran salido de [selectionFor].
  List<Selection> optionsFor(Selection selection) {
    final entry = node(selection.entryId);
    if (entry == null) return const [];

    final options = <Selection>[];
    for (final child in _childLinks(entry)) {
      options.add(_selectionFrom(child.entry,
          groupId: null, groupName: null, groupConstraints: const [], link: child.link));
    }
    for (final (:group, :link) in _allGroupsOf(entry)) {
      final groupRules = [
        for (final node_ in [group, if (link != null) link])
          for (final c in (node_['constraints'] as List? ?? const []))
            Constraint.fromNode(c as Map<String, dynamic>),
      ];
      final groupChanges = [
        for (final node_ in [group, if (link != null) link]) ...Modifier.allOf(node_),
      ];
      for (final option in _childLinks(group)) {
        options.add(_selectionFrom(option.entry,
            groupId: group['id'] as String?,
            groupName: group['name'] as String?,
            groupConstraints: groupRules,
            groupModifiers: groupChanges,
            link: option.link));
      }
    }
    return options;
  }

  Selection _selectionFrom(
    Map<String, dynamic> entry, {
    required String? groupId,
    required String? groupName,
    required List<Constraint> groupConstraints,
    Map<String, dynamic>? link,
    List<Modifier> groupModifiers = const [],
    int count = 1,
  }) {
    final constraints = [
      for (final node_ in [entry, if (link != null) link])
        for (final raw in (node_['constraints'] as List? ?? const []))
          Constraint.fromNode(raw as Map<String, dynamic>),
    ];
    final selection = Selection(
      entryId: entry['id'] as String? ?? '',
      name: entry['name'] as String? ?? '',
      type: entry['type'] as String? ?? '',
      baseCosts: _costsOf(entry),
      count: count,
      groupId: groupId,
      groupName: groupName,
      constraints: constraints,
      groupConstraints: groupConstraints,
      modifiers: [Modifier.allOf(entry), if (link != null) Modifier.allOf(link)].expand((m) => m).toList(),
      groupModifiers: groupModifiers,
      categoryIds: [
        for (final raw in (entry['categoryLinks'] as List? ?? const []))
          if ((raw as Map<String, dynamic>)['targetId'] is String) raw['targetId'] as String,
      ],
    );

    for (final child in _childLinks(entry)) {
      final minimum = _minimumSelections(child.entry);
      if (minimum > 0) {
        selection.addChild(_selectionFrom(child.entry,
            groupId: null,
            groupName: null,
            groupConstraints: const [],
            link: child.link,
            count: minimum));
      }
    }

    for (final (:group, :link) in _allGroupsOf(entry)) {
      final groupRules = [
        for (final node_ in [group, if (link != null) link])
          for (final c in (node_['constraints'] as List? ?? const []))
            Constraint.fromNode(c as Map<String, dynamic>),
      ];
      final groupChanges = [
        for (final node_ in [group, if (link != null) link]) ...Modifier.allOf(node_),
      ];
      for (final option in _childLinks(group)) {
        final minimum = _minimumSelections(option.entry);
        if (minimum > 0) {
          selection.addChild(_selectionFrom(option.entry,
              groupId: group['id'] as String?,
              groupName: group['name'] as String?,
              groupConstraints: groupRules,
              groupModifiers: groupChanges,
              link: option.link,
              count: minimum));
        }
      }
    }

    return selection;
  }

  /// Las entradas hijas de un nodo, estén incrustadas o lleguen por enlace.
  Iterable<Map<String, dynamic>> _childEntries(Map<String, dynamic> node_) =>
      _childLinks(node_).map((child) => child.entry);

  /// Igual, pero conservando el enlace por el que se llega a cada una.
  ///
  /// El enlace no es un puntero y ya: es donde el dataset **ajusta lo compartido a este sitio**.
  /// La misma entrada «Reaver Wargear» permite una opción en general y dos cuando se llega a ella
  /// desde según qué miniatura, y quien lo dice es un modifier del enlace sobre una restricción.
  /// Resolver solo el destino se lleva por delante ese ajuste.
  Iterable<({Map<String, dynamic> entry, Map<String, dynamic>? link})> _childLinks(
      Map<String, dynamic> node_) sync* {
    for (final raw in (node_['selectionEntries'] as List? ?? const [])) {
      yield (entry: raw as Map<String, dynamic>, link: null);
    }
    for (final raw in (node_['entryLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      // Un enlace a un grupo trae un grupo de opciones, no una opción: lo recoge `_groupsOf`.
      if (link['type'] == 'selectionEntryGroup') continue;
      final target = node(link['targetId'] as String? ?? '');
      if (target != null) yield (entry: target, link: link);
    }
  }

  int _minimumSelections(Map<String, dynamic> entry) {
    for (final raw in (entry['constraints'] as List? ?? const [])) {
      final constraint = raw as Map<String, dynamic>;
      if (constraint['type'] == 'min' && constraint['field'] == 'selections') {
        final value = constraint['value'];
        if (value is num) return value.round();
      }
    }
    return 0;
  }

  /// Todos los perfiles que hacen falta para la ficha de una unidad.
  ///
  /// No basta con los suyos. La línea de características y las habilidades sí cuelgan de la
  /// unidad, pero **las armas no**: viven en las opciones de sus miniaturas, un par de niveles más
  /// abajo. Una ficha que solo mire la entrada sale sin armas.
  ///
  /// Vienen sin repetir y en el orden en que se encuentran, que deja la línea de la unidad la
  /// primera. La interfaz los agrupa por [Profile.typeName].
  List<Profile> sheetOf(UnitEntry unit) {
    final entry = node(unit.id);
    if (entry == null) return const [];

    final profiles = <String, Profile>{};
    final visited = <String>{};

    void collect(Map<String, dynamic> node_, int depth) {
      if (depth > 4) return;
      if (!visited.add(node_['id'] as String? ?? '')) return;
      for (final profile in profilesOf(node_)) {
        profiles.putIfAbsent('${profile.typeName}|${profile.name}', () => profile);
      }
      for (final child in _childLinks(node_)) {
        collect(child.entry, depth + 1);
      }
      for (final group in _groupsOf(node_)) {
        for (final option in _childLinks(group)) {
          collect(option.entry, depth + 1);
        }
      }
    }

    collect(entry, 0);
    return profiles.values.toList();
  }

  /// Los perfiles de una entrada, incluidos los que llegan por enlace.
  ///
  /// La mayoría de las habilidades no están incrustadas en la unidad: son perfiles compartidos a
  /// los que apunta un `infoLink`. Sin resolverlos, una unidad se muestra sin reglas.
  List<Profile> profilesOf(Map<String, dynamic> entry) {
    final profiles = <Profile>[];
    for (final raw in (entry['profiles'] as List? ?? const [])) {
      profiles.add(Profile.fromNode(raw as Map<String, dynamic>));
    }
    for (final raw in (entry['infoLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      final target = node(link['targetId'] as String? ?? '');
      if (target != null && target.containsKey('characteristics')) {
        profiles.add(Profile.fromNode(target));
      }
    }
    return profiles;
  }
}
