import 'dart:convert';
import 'dart:io';

import 'detachment.dart';
import 'model.dart';
import 'notas.dart';
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

  /// Carga los ficheros JSON de [directory], y con [notas] las opciones de equipo de la hoja.
  ///
  /// Espera el dataset completo, no un fichero suelto: los ficheros se referencian entre ellos.
  ///
  /// Las notas van aparte y son opcionales: no son un catálogo —no se resuelven ni se validan— y
  /// sin ellas la app funciona igual, solo que enseñando los topes calculados y no la frase.
  static Future<Dataset> load(Directory directory, {File? notas}) async {
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw ArgumentError('El directorio no contiene ficheros del dataset: ${directory.path}');
    }
    final dataset = fromJson([for (final file in files) await file.readAsString()]);
    if (notas != null && notas.existsSync()) {
      dataset.notasDeEquipo = NotasDeEquipo.desdeJson(await notas.readAsString());
    }
    return dataset;
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
      units.add(_toUnit(target, link));
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

    for (final group in _gruposDeDetachment(faction.node)) {
      for (final option in _entradasDeDetachment(group)) {
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
    return detachments;
  }

  /// El grupo de detachments del que come una facción.
  ///
  /// Cada catálogo lista los suyos en su propio grupo «Detachment», y cuando los comparte con
  /// otra facción no los copia: **enlaza el grupo de su librería**. Tyranids y Genestealer Cults
  /// enlazan los dos el de Library - Tyranids, y las condiciones de `primary-catalogue` reparten
  /// cuáles ve cada uno.
  ///
  /// Partir del catálogo entero en vez de este grupo era lo que colaba detachments ajenos: un
  /// ejército de Custodes enlaza Agents of the Imperium para poder llevar sus unidades como
  /// aliadas, y con ello aparecían los del Ordo Xenos como detachment elegible.
  ///
  /// Solo hereda quien no tiene grupo propio: los capítulos de Space Marines no declaran ni uno y
  /// los suyos viven en el catálogo de Space Marines. Entre varios candidatos se coge el que más
  /// declare, que es del que cuelga de verdad; el aliado que también se enlaza aporta cinco y
  /// nunca gana.
  Iterable<Map<String, dynamic>> _gruposDeDetachment(Map<String, dynamic> catalogue) {
    final propios = _gruposDetachmentEn(catalogue).toList();
    if (propios.isNotEmpty) return propios;

    // Solo los que el catálogo enlaza **directamente**. Siguiendo la cadena se llega a catálogos
    // que la facción ni menciona: Chaos Knights acababa en Chaos Space Marines y enseñaba los
    // diecisiete suyos en vez de los ocho de su librería.
    final candidatos = <({Map<String, dynamic> catalogo, List<Map<String, dynamic>> grupos})>[];
    for (final raw in (catalogue['catalogueLinks'] as List? ?? const [])) {
      final target = node((raw as Map<String, dynamic>)['targetId'] as String? ?? '');
      if (target == null) continue;
      final suyos = _gruposDetachmentEn(target).toList();
      if (suyos.isNotEmpty) candidatos.add((catalogo: target, grupos: suyos));
    }
    if (candidatos.isEmpty) return const [];

    // De quién cuelga se nota en el nombre: «Chaos Knights» tira de «Chaos Knights Library» y no
    // de «Chaos Daemons Library». Cuando no hay parecido —los capítulos de Space Marines no se
    // llaman como su catálogo— decide quién declara más: el aliado que también se enlaza aporta
    // un puñado y nunca gana.
    final mias = _palabrasDe(catalogue['name'] as String? ?? '');
    candidatos.sort((a, b) {
      final ca = _palabrasDe(a.catalogo['name'] as String? ?? '').intersection(mias).length;
      final cb = _palabrasDe(b.catalogo['name'] as String? ?? '').intersection(mias).length;
      if (ca != cb) return cb.compareTo(ca);
      return _cuantosEn(b.grupos).compareTo(_cuantosEn(a.grupos));
    });
    return candidatos.first.grupos;
  }

  /// Las palabras con las que se reconoce un catálogo, sin el bando ni la coletilla de librería.
  static Set<String> _palabrasDe(String nombre) {
    final ultimo = nombre.split(' - ').last.replaceAll('Library', '');
    return {
      for (final palabra in ultimo.split(RegExp(r'\s+')))
        if (palabra.length > 3) palabra,
    };
  }

  int _cuantosEn(List<Map<String, dynamic>> grupos) =>
      grupos.fold(0, (total, g) => total + _entradasDeDetachment(g).length);

  /// Los grupos «Detachment» declarados dentro de un catálogo, sin salirse de él.
  Iterable<Map<String, dynamic>> _gruposDetachmentEn(Map<String, dynamic> catalogue) sync* {
    for (final nodo in _todoDe(catalogue)) {
      if (_isDetachmentGroup(nodo)) yield nodo;
    }
  }

  /// Los detachments de un grupo: los suyos y los de los grupos que enlaza.
  ///
  /// El enlace a otro grupo es como una facción toma prestada la lista de su librería sin
  /// copiarla, así que sin seguirlo Tyranids y Genestealer Cults se quedan sin ninguno.
  Iterable<Map<String, dynamic>> _entradasDeDetachment(Map<String, dynamic> group,
      [Set<String>? seen]) sync* {
    final visited = seen ?? <String>{};
    if (!visited.add(group['id'] as String? ?? '')) return;
    yield* _childEntries(group);
    for (final enlazado in _groupLinks(group)) {
      yield* _entradasDeDetachment(enlazado.group, visited);
    }
  }

  /// Todo lo que cuelga de un catálogo, sin salirse de él.
  Iterable<Map<String, dynamic>> _todoDe(Map<String, dynamic> nodo) sync* {
    yield nodo;
    for (final clave in const [
      'selectionEntries',
      'selectionEntryGroups',
      'sharedSelectionEntries',
      'sharedSelectionEntryGroups',
    ]) {
      for (final raw in (nodo[clave] as List? ?? const [])) {
        yield* _todoDe(raw as Map<String, dynamic>);
      }
    }
  }


  /// Los tipos de coste que solo se usan en Crusade, leídos del propio sistema de juego.
  late final Set<String> crusadeCostTypeIds = {
    for (final root in _roots)
      for (final raw in (root['costTypes'] as List? ?? const []))
        if (((raw as Map<String, dynamic>)['name'] as String? ?? '').startsWith('Crusade'))
          raw['id'] as String,
  };

  /// Secciones que el dataset trae para Crusade y que no pintan nada en una partida normal.
  ///
  /// El dataset **no las marca de ninguna manera**: no las esconde con un modifier, no las mete en
  /// una categoría propia y no las ata al tipo de fuerza, así que no hay señal que seguir y el
  /// criterio lo pone esta capa. Se reconocen por su coste —hay cuatro tipos de coste que solo
  /// existen en Crusade— y, cuando no cuestan nada, por el nombre de su sección.
  ///
  /// Se comprobó sobre el dataset entero antes de aplicarlo: de las opciones que esto esconde,
  /// **ninguna cuesta puntos y ninguna es una mejora**, así que no se pierde nada de una lista de
  /// partida normal. Con `crusade: true` se recuperan.
  static const crusadeGroupNames = {
    'Crusade',
    'Battle Tallies',
    'Battle Traits',
    'Weapon Modifications',
    'Order of Battle',
  };

  bool _isCrusadeGroup(Map<String, dynamic> group) {
    if (crusadeGroupNames.contains(group['name'])) return true;
    final options = _childLinks(group).map((o) => o.entry).toList();
    if (options.isEmpty) return false;
    return options.every((option) => (option['costs'] as List? ?? const []).any((raw) {
          final cost = raw as Map<String, dynamic>;
          return crusadeCostTypeIds.contains(cost['typeId']) &&
              ((cost['value'] as num?) ?? 0) > 0;
        }));
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

  /// Los interruptores de «Show/Hide Options», que deciden qué contenido entra en la lista.
  ///
  /// El dataset esconde por defecto las unidades Legends, los Imperial Agents, los Knights
  /// aliados, las fortificaciones y los demonios de cada dios, y los enseña solo si el jugador
  /// enciende el interruptor correspondiente. Son 18, y afectan al 76,7 % de las unidades: sin
  /// evaluarlos, el selector de unidades ofrece medio dataset que la lista no puede llevar.
  /// Son **por facción**: cada catálogo añade los suyos a la entrada «Show/Hide Options», así que
  /// los cuatro del sistema son solo los comunes y los de demonios llegan con la librería de
  /// Chaos Daemons. Buscando uno solo se pierden catorce.
  List<Rule> visibilityOptionsOf(Faction faction) {
    final options = <String, Rule>{};
    for (final link in _rootLinks(faction.node)) {
      final target = node(link['targetId'] as String? ?? '');
      if (link['name'] != 'Show/Hide Options' && target?['name'] != 'Show/Hide Options') {
        continue;
      }
      // Los del enlace **y** los del destino: cada catálogo cuelga los suyos del enlace, y los
      // cuatro comunes están en la entrada compartida del sistema. Mirando solo una parte, una
      // facción se queda sin la mitad de sus interruptores.
      for (final node_ in [link, if (target != null) target]) {
        for (final option in _childEntries(node_)) {
          final id = option['id'] as String? ?? '';
          options.putIfAbsent(
              id,
              () => Rule(id: id, name: option['name'] as String? ?? '', description: ''));
        }
      }
    }
    return options.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

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

  /// Las categorías con las que el dataset marca a un aliado, por identificador.
  ///
  /// El sistema de juego declara nueve —«Allies: Chaos Knights», «Allies: Imperial Agents»…— y
  /// cada unidad del catálogo aliado lleva un modifier `set-primary` a la suya, condicionado a que
  /// el catálogo principal **no** sea el propio. Es decir: el dataset ya dice que en una lista
  /// ajena su rol no es Character ni Vehicle, sino aliado. Leerlas de aquí en vez de escribirlas a
  /// mano es lo que hace que valga para las 36 facciones y siga valiendo si upstream añade otra.
  late final Map<String, String> allyCategories = () {
    final categories = <String, String>{};
    for (final root in _roots) {
      for (final key in const ['categoryEntries', 'sharedCategoryEntries']) {
        for (final raw in (root[key] as List? ?? const [])) {
          final entry = raw as Map<String, dynamic>;
          final name = entry['name'] as String? ?? '';
          if (!name.startsWith('Allies:')) continue;
          final id = entry['id'] as String?;
          if (id != null) categories[id] = name.substring('Allies:'.length).trim();
        }
      }
    }
    return categories;
  }();

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

  /// Los grupos de opciones de un nodo, estén incrustados o lleguen por enlace.
  Iterable<Map<String, dynamic>> _groupsOf(Map<String, dynamic> node_) =>
      _groupLinks(node_).map((group) => group.group);

  /// Todos los grupos que cuelgan de un nodo, incluidos los que anidan otros grupos.
  ///
  /// El dataset los anida: «Heavy Weapons» no cuelga del tanque sino de su grupo «Wargear». Sin
  /// bajar, ni se despliegan sus mínimos obligatorios ni se pueden ofrecer sus opciones.
  Iterable<
      ({
        Map<String, dynamic> group,
        Map<String, dynamic>? link,
        List<Modifier> inherited,
        String? parentId
      })> _allGroupsOf(Map<String, dynamic> node_, bool crusade,
          [Set<String>? seen, List<Modifier> inherited = const [], String? parentId]) sync* {
    final visited = seen ?? <String>{};
    for (final entry in _groupLinks(node_)) {
      if (!visited.add(entry.group['id'] as String? ?? '')) continue;
      // Las secciones de Crusade se saltan enteras, con lo que anidan dentro.
      if (!crusade && _isCrusadeGroup(entry.group)) continue;
      yield (
        group: entry.group,
        link: entry.link,
        inherited: inherited,
        parentId: parentId
      );
      // Lo que el grupo declara vale también para lo que anida: una mejora se esconde por lo que
      // diga el grupo «Enhancements» que la contiene, no por lo que diga ella.
      final propios = [
        for (final node_ in [entry.group, if (entry.link != null) entry.link!])
          ...Modifier.allOf(node_),
      ];
      yield* _allGroupsOf(entry.group, crusade, visited, [...inherited, ...propios],
          entry.group['id'] as String?);
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

  UnitEntry _toUnit(Map<String, dynamic> entry, [Map<String, dynamic>? link]) {
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
      // También los del enlace: es donde una facción ajusta lo que hereda de un catálogo común.
      visibility: [
        for (final node_ in [entry, if (link != null) link])
          for (final modifier in Modifier.allOf(node_))
            if (modifier.field == 'hidden') modifier,
      ],
      categoryModifiers: [
        for (final node_ in [entry, if (link != null) link])
          for (final modifier in Modifier.allOf(node_))
            if (modifier.field == 'category') modifier,
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
  List<Selection> optionsFor(Selection selection, {bool crusade = false}) {
    final entry = node(selection.entryId);
    if (entry == null) return const [];

    final options = <Selection>[];
    for (final child in _childLinks(entry)) {
      options.add(_selectionFrom(child.entry,
          groupId: null,
          groupName: null,
          groupConstraints: const [],
          link: child.link,
          crusade: crusade));
    }
    for (final (:group, :link, :inherited, parentId: _) in _allGroupsOf(entry, crusade)) {
      final groupRules = [
        for (final node_ in [group, if (link != null) link])
          for (final c in (node_['constraints'] as List? ?? const []))
            Constraint.fromNode(c as Map<String, dynamic>),
      ];
      final groupChanges = [
        ...inherited,
        for (final node_ in [group, if (link != null) link]) ...Modifier.allOf(node_),
      ];
      for (final option in _childLinks(group)) {
        options.add(_selectionFrom(option.entry,
            groupId: group['id'] as String?,
            groupName: group['name'] as String?,
            groupConstraints: groupRules,
            groupModifiers: groupChanges,
            link: option.link,
            crusade: crusade));
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
    bool crusade = false,
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
      groups: [],
      categoryIds: [
        for (final raw in (entry['categoryLinks'] as List? ?? const []))
          if ((raw as Map<String, dynamic>)['targetId'] is String) raw['targetId'] as String,
      ],
      primaryCategoryId: (entry['categoryLinks'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((link) => link['primary'] == true && link['targetId'] is String)
          .map((link) => link['targetId'] as String)
          .firstOrNull,
    );

    for (final child in _childLinks(entry)) {
      final minimum = _minimumSelections(child.entry, child.link);
      if (minimum > 0) {
        selection.addChild(_selectionFrom(child.entry,
            groupId: null,
            groupName: null,
            groupConstraints: const [],
            link: child.link,
            crusade: crusade,
            count: minimum));
      }
    }

    for (final (:group, :link, :inherited, :parentId) in _allGroupsOf(entry, crusade)) {
      final groupRules = [
        for (final node_ in [group, if (link != null) link])
          for (final c in (node_['constraints'] as List? ?? const []))
            Constraint.fromNode(c as Map<String, dynamic>),
      ];
      final groupChanges = [
        ...inherited,
        for (final node_ in [group, if (link != null) link]) ...Modifier.allOf(node_),
      ];
      selection.groups.add(OptionGroup(
        id: group['id'] as String? ?? '',
        name: group['name'] as String?,
        constraints: groupRules,
        modifiers: groupChanges,
        parentId: parentId,
        defaultId: _defectoDe(group),
      ));
      final options = _childLinks(group).toList();
      var puestas = 0;
      for (final option in options) {
        final minimum = _minimumSelections(option.entry, option.link);
        if (minimum > 0) {
          puestas += minimum;
          selection.addChild(_selectionFrom(option.entry,
              groupId: group['id'] as String?,
              groupName: group['name'] as String?,
              groupConstraints: groupRules,
              groupModifiers: groupChanges,
              link: option.link,
              crusade: crusade,
              count: minimum));
        }
      }

      // Si el grupo exige un mínimo, se rellena con lo que el dataset marca por defecto. Es el
      // equipo con el que viene la miniatura en su hoja de datos: el Defiler trae su lanzamisiles,
      // su cañón Hades y su baleflamer, y los grupos «Replace...» están para cambiarlos, no para
      // obligarte a elegir de cero. Una escuadra de Plague Marines trae cuatro con bólter.
      //
      // Sin esto la unidad nace desnuda e incumpliendo, y hay que armarla entera a mano aunque el
      // dataset diga exactamente con qué viene.
      final required = _minimumOf(groupRules);
      if (puestas < required) {
        final porDefecto = group['defaultSelectionEntryId'] as String?;
        final elegida = porDefecto != null
            ? options
                .where((o) =>
                    o.entry['id'] == porDefecto || o.link?['id'] == porDefecto)
                .firstOrNull
            // Sin defecto declarado: si solo una de las opciones puede cubrir el grupo ella sola
            // —su techo llega al mínimo que se pide— esa es la básica y las demás son armas
            // especiales con tope de una o dos. «Nueve Kabalite Warriors» ofrece cinco cosas y
            // solo el guerrero raso puede ser nueve.
            : (options.length == 1 ? options.single : _basicaDe(options, required));
        if (elegida != null) {
          // Sin pasarse del techo de la propia opción: hay grupos que piden nueve miniaturas y
          // cuyo defecto es un campeón con un máximo de uno. Multiplicar sin mirar dejaba nueve
          // campeones donde cabía uno, y la unidad nacía ilegal.
          final tope = _maximumSelections(elegida.entry, elegida.link);
          var cuantas = required - puestas;
          if (tope != null && cuantas > tope) cuantas = tope;
          // Si ya hay un montón de eso mismo, se le suma en vez de abrir otro. Dos montones del
          // mismo modelo hacen que una restricción por entrada («mínimo 6 Wyches») se compruebe
          // contra uno solo de los dos y salte un aviso falso.
          final yaHay = selection.children
              .where((c) => c.entryId == elegida.entry['id'])
              .firstOrNull;
          if (cuantas > 0 && yaHay != null) {
            yaHay.count += cuantas;
          } else if (cuantas > 0) {
            selection.addChild(_selectionFrom(elegida.entry,
                groupId: group['id'] as String?,
                groupName: group['name'] as String?,
                groupConstraints: groupRules,
                groupModifiers: groupChanges,
                link: elegida.link,
                crusade: crusade,
                count: cuantas));
          }
        }
      }
    }

    return selection;
  }

  /// La única opción de un grupo capaz de cubrir su mínimo ella sola, si hay una sola así.
  ///
  /// Es como el dataset distingue al soldado raso del arma especial sin decirlo: el raso no lleva
  /// techo o lo lleva alto, y las especiales lo llevan en una o dos. Si hay más de una candidata
  /// no se elige por el jugador.
  ({Map<String, dynamic> entry, Map<String, dynamic>? link})? _basicaDe(
      List<({Map<String, dynamic> entry, Map<String, dynamic>? link})> options, int required) {
    if (required < 1) return null;
    final candidatas = options.where((o) {
      final tope = _maximumSelections(o.entry, o.link);
      return tope == null || tope >= required;
    }).toList();
    return candidatas.length == 1 ? candidatas.single : null;
  }

  /// El techo que una entrada declara para sí misma, mirando también su enlace. `null` si no pone.
  int? _maximumSelections(Map<String, dynamic> entry, [Map<String, dynamic>? link]) {
    int? tope;
    for (final node_ in [entry, if (link != null) link]) {
      for (final raw in (node_['constraints'] as List? ?? const [])) {
        final constraint = raw as Map<String, dynamic>;
        if (constraint['type'] != 'max' || constraint['field'] != 'selections') continue;
        final value = constraint['value'];
        if (value is num && value >= 0 && (tope == null || value < tope)) {
          tope = value.round();
        }
      }
    }
    return tope;
  }

  /// Cuál es la opción de serie de un grupo, ya resuelta al id con el que se la reconoce luego.
  ///
  /// `defaultSelectionEntryId` unas veces apunta a la entrada de destino y otras al enlace por el
  /// que se llega a ella. Guardar el valor crudo no sirve: al buscarlo entre las opciones, la
  /// mitad no casan.
  String? _defectoDe(Map<String, dynamic> group) {
    final marcado = group['defaultSelectionEntryId'] as String?;
    if (marcado == null) return null;
    for (final option in _childLinks(group)) {
      if (option.entry['id'] == marcado || option.link?['id'] == marcado) {
        return option.entry['id'] as String?;
      }
    }
    return null;
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

  /// El mínimo que exige un grupo, mirando solo lo que declara. Sin modifiers: aquí no hay lista
  /// todavía contra la que evaluarlos, y equivocarse por exceso metería opciones que sobran.
  static int _minimumOf(List<Constraint> constraints) {
    for (final constraint in constraints) {
      if (constraint.type == 'min' && constraint.field == 'selections' && constraint.value > 0) {
        return constraint.value.round();
      }
    }
    return 0;
  }

  /// El mínimo que exige una entrada, mirando también el enlace por el que se llega a ella.
  ///
  /// El enlace no es un puntero: es donde el dataset ajusta lo compartido a este sitio, y ahí
  /// escribe mínimos tan a menudo como en el destino. La Plasma gun del Plague Marine con plasma
  /// lleva su `min 1` en el enlace y la Blight launcher en el destino; mirando solo el destino, el
  /// marine de plasma nacía desarmado y el de blight launcher no, sin ninguna razón visible.
  int _minimumSelections(Map<String, dynamic> entry, [Map<String, dynamic>? link]) {
    for (final node_ in [entry, if (link != null) link]) {
      for (final raw in (node_['constraints'] as List? ?? const [])) {
        final constraint = raw as Map<String, dynamic>;
        if (constraint['type'] == 'min' && constraint['field'] == 'selections') {
          final value = constraint['value'];
          if (value is num) return value.round();
        }
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
    final cached = _sheetCache[unit.id];
    if (cached != null) return cached;
    final entry = node(unit.id);
    if (entry == null) return const [];

    final profiles = <String, Profile>{};
    final visited = <String>{};

    void collect(Map<String, dynamic> node_, int depth) {
      if (depth > 4) return;
      if (!visited.add(node_['id'] as String? ?? '')) return;
      // Las mejoras no son de la unidad: son del detachment, y cualquier personaje puede llevar
      // una. Metiéndolas aquí, la hoja del Daemon Prince of Nurgle salía con 26 de sus 33
      // perfiles ocupados por mejoras que no lleva puestas, y había que bajar ocho pantallas para
      // encontrar sus habilidades. En todo el dataset son 7.565 perfiles colados en 717 unidades.
      if (enhancementIds.contains(node_['id'])) return;
      for (final profile in profilesOf(node_)) {
        if (_esGlosarioDeArma(profile)) continue;
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
    return _sheetCache[unit.id] = profiles.values.toList();
  }

  /// La hoja de una unidad se arma recorriendo su árbol entero y se pide muchas veces: al pintar
  /// la ficha, al buscar a quién se une un líder y al mirar si acepta a otro. Resolverla una vez.
  final Map<String, List<Profile>> _sheetCache = {};

  /// Si una hoja trae escrita su excepción de líder. Se pregunta por cada anfitriona posible.
  final Map<String, bool> _excepcionCache = {};

  /// Si un perfil de habilidad es en realidad la explicación de una palabra clave de arma.
  ///
  /// El dataset cuelga de la unidad un perfil llamado «Precise» cuyo texto es «cada vez que se
  /// consigue una herida crítica **con esta arma**…», que es la explicación de [PRECISION]. Eso no
  /// es una habilidad de la unidad: lo dice el propio texto, que habla de un arma y no de ella.
  /// Son 594 unidades con esa línea de más en su hoja, muchas de ellas vehículos y titánicas, que
  /// es donde más canta.
  ///
  /// Se reconoce por eso mismo —una habilidad de unidad no habla de «esta arma»— y no por el
  /// nombre: así vale para cualquier otra que upstream cuelgue igual. Hoy solo cae esa.
  static bool _esGlosarioDeArma(Profile profile) {
    if (profile.typeName != 'Abilities') return false;
    final texto = (profile.description ?? '').toLowerCase();
    return texto.contains('con esta arma') ||
        texto.contains('de esta arma') ||
        texto.contains('esta arma tiene') ||
        texto.contains('with this weapon') ||
        texto.contains('this weapon has');
  }

  /// Todas las mejoras del dataset, por identificador.
  ///
  /// Una mejora es una opción con coste en puntos que el dataset esconde salvo que se haya elegido
  /// un detachment; es la misma definición que usa [enhancementsOf], solo que sin preguntar por
  /// cuál. Se calcula de una vez recorriendo cada catálogo, que es lo que permite quitarlas de la
  /// hoja de datos sin tener que resolver antes las mejoras de las 36 facciones.
  late final Set<String> enhancementIds = () {
    final ids = <String>{};
    for (final root in _roots) {
      _collectEnhancements(root, const {}, (entry, gates) {
        if (gates.isEmpty) return;
        // Un arma de pago atada a un detachment cumple la misma definición —opción con puntos y
        // escondida— y no es una mejora: es un arma. Se distinguen por su perfil, que en un arma
        // es una línea de características y en una mejora un texto de habilidad. Son 21 en el
        // dataset: el Dark Lance, el Psycannon, el Thunder Hammer, la Ballistus Lascannon…
        //
        // Y también cuando el arma cuelga de la opción en vez de estar en ella, que es como se
        // arman los personajes [Crucible]: la opción se paga y el perfil está un nivel más abajo.
        if (_traeArma(entry, 0)) return;
        final id = entry['id'] as String?;
        if (id != null) ids.add(id);
      });
    }
    return ids;
  }();

  /// Si una entrada trae un arma, en ella o justo debajo.
  bool _traeArma(Map<String, dynamic> entry, int depth) {
    if (profilesOf(entry).any((p) => p.typeName.contains('Weapons'))) return true;
    if (depth >= 2) return false;
    for (final child in _childLinks(entry)) {
      if (_traeArma(child.entry, depth + 1)) return true;
    }
    for (final group in _groupsOf(entry)) {
      for (final option in _childLinks(group)) {
        if (_traeArma(option.entry, depth + 1)) return true;
      }
    }
    return false;
  }

  /// La hoja de datos de lo que una unidad lleva puesto **ahora mismo**, no de todo lo que podría.
  ///
  /// [sheetOf] enseña el catálogo entero de la unidad, que es lo que hace falta al mirarla antes de
  /// meterla en la lista: ahí se comparan las armas que puede llevar. Dentro de la lista es al
  /// revés y estorba: si a los Plague Marines les he quitado todos los bólters, el bólter no pinta
  /// nada en su hoja, y el Caladius Grav-tank tiene que enseñar el cañón que le he puesto y no los
  /// tres que no.
  ///
  /// La línea de características y las habilidades siempre salen de la entrada de la unidad,
  /// estén o no entre lo elegido: no se eligen, se tienen.
  List<Profile> sheetOfSelection(Selection selection) {
    final profiles = <String, Profile>{};
    final entry = node(selection.entryId);

    void anota(Map<String, dynamic> node_, {bool armas = true}) {
      for (final profile in profilesOf(node_)) {
        // Las armas solo entran por lo elegido. Una miniatura de la entrada trae colgadas las
        // suyas de serie, y recogerlas aquí devolvía el bólter a la hoja de unos Plague Marines a
        // los que se lo había quitado, que es justo lo que se quiere evitar.
        if (!armas && profile.typeName.contains('Weapons')) continue;
        profiles.putIfAbsent('${profile.typeName}|${profile.name}', () => profile);
      }
    }

    // Lo que la unidad es: su línea de características y sus habilidades. Cuelgan de la entrada y
    // de las miniaturas que la componen, y esas no se eligen, se tienen.
    if (entry != null) {
      anota(entry, armas: false);
      for (final child in _childLinks(entry)) {
        if (child.entry['type'] == 'model') anota(child.entry, armas: false);
      }
    }
    // Y lo que lleva puesto, sea un arma, una miniatura o una mejora.
    for (final node_ in selection.descendantsAndSelf) {
      final suyo = node(node_.entryId);
      if (suyo != null) anota(suyo);
    }
    return profiles.values.toList();
  }

  /// Las opciones de equipo tal y como las dice la hoja impresa, si se han cargado.
  ///
  /// No decide nada: los topes, la validación y el precio siguen saliendo del dataset. Esto es la
  /// frase que explica qué se está eligiendo, que BSData no trae. Ver [NotasDeEquipo].
  NotasDeEquipo get notasDeEquipo => _notasDeEquipo;

  set notasDeEquipo(NotasDeEquipo notas) {
    _notasDeEquipo = notas;
    // Lo ya contrastado deja de valer: se contrastó contra otras notas.
    _notasCache.clear();
  }

  NotasDeEquipo _notasDeEquipo = const NotasDeEquipo.vacia();

  /// Lo que la hoja dice que se puede cambiar en esta unidad, **si sigue valiendo**.
  ///
  /// El texto es de las index cards de 10ª y hay hojas que han cambiado entera: el Defiler de
  /// entonces llevaba un twin heavy flamer y un reaper autocannon, y el de ahora un baleflamer y
  /// un cañón Hades. Enseñar esa frase sería peor que no enseñar ninguna, porque el jugador la
  /// creería y no encontraría ni una de las armas que nombra.
  ///
  /// Así que cada frase se contrasta con lo que la unidad tiene hoy: si las armas que nombra no
  /// están entre sus opciones ni entre sus perfiles, se cae. Lo que queda es lo que sigue siendo
  /// verdad, y lo que se cae lo suple el tope calculado, que sale del dataset y siempre está al día.
  List<String> wargearNotesOf(UnitEntry unit) {
    final cached = _notasCache[unit.id];
    if (cached != null) return cached;
    final todas = notasDeEquipo.of(unit);
    if (todas.isEmpty) return _notasCache[unit.id] = const [];

    final vocabulario = _vocabularioDe(unit);
    final buenas = [
      for (final nota in todas)
        if (_sigueValiendo(nota, vocabulario)) nota,
    ];
    return _notasCache[unit.id] = buenas;
  }

  final Map<String, List<String>> _notasCache = {};

  /// Todo lo que esta unidad puede llamar suyo, palabra a palabra: sus armas, sus opciones, sus
  /// miniaturas y los nombres de sus grupos de equipo.
  Set<String> _vocabularioDe(UnitEntry unit) {
    final palabras = <String>{};
    void anota(String? texto) {
      if (texto == null) return;
      for (final palabra in texto.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (palabra.length >= 4) palabras.add(palabra);
      }
    }

    for (final profile in sheetOf(unit)) {
      anota(profile.name);
    }
    final entry = node(unit.id);
    if (entry == null) return palabras;
    final visto = <String>{};
    void recorre(Map<String, dynamic> node_, int depth) {
      if (depth > 4 || !visto.add(node_['id'] as String? ?? '')) return;
      anota(node_['name'] as String?);
      for (final child in _childLinks(node_)) {
        recorre(child.entry, depth + 1);
      }
      for (final (:group, link: _, inherited: _, parentId: _) in _allGroupsOf(node_, false)) {
        anota(group['name'] as String?);
        for (final option in _childLinks(group)) {
          recorre(option.entry, depth + 1);
        }
      }
    }

    recorre(entry, 0);
    return palabras;
  }

  /// Si lo que nombra una frase sigue estando en la unidad.
  ///
  /// Se compara **por palabras enteras**, no por trozos: buscando trozos, el «scourge» del Defiler
  /// de 10ª casaba con el «Electroscourge» de 11ª y el «flamer» con el «baleflamer», y la frase
  /// vieja se daba por buena. Por palabras, esa frase saca 3 de 7 y se cae, que es lo que tiene
  /// que pasar.
  ///
  /// Se piden **más de dos tercios**, no el pleno: el texto nombra armas que en el dataset viven
  /// dentro del nombre de la miniatura que las lleva, y alguna palabra se pierde siempre. Con dos
  /// tercios cae la frase del Defiler —nombra un twin heavy bolter que ya no existe y saca 4 de
  /// 6— y se quedan las de los Plague Marines y los Terminators, que sacan el pleno.
  ///
  /// El corte no es delicado: entre pedir la mitad y pedir el 80 % solo se mueve un 12 % de las
  /// frases, así que el sitio exacto del listón cambia poco y lo que decide es el criterio.
  static bool _sigueValiendo(String nota, Set<String> vocabulario) {
    final suyas = _palabrasDeContenido(nota);
    if (suyas.isEmpty) return true;
    final encontradas = suyas.where(vocabulario.contains).length;
    return encontradas * 3 > suyas.length * 2;
  }

  /// Las palabras de una frase que dicen algo: fuera la gramática y fuera los números.
  static Set<String> _palabrasDeContenido(String texto) => {
        for (final palabra in texto.toLowerCase().split(RegExp(r"[^a-z]+")))
          if (palabra.length >= 4 && !_gramatica.contains(palabra)) palabra,
      };

  /// Lo que aparece en todas las frases y no distingue una hoja de otra.
  static const _gramatica = {
    'this', 'that', 'with', 'their', 'them', 'they', 'have', 'each', 'from',
    'model', 'models', 'unit', 'units', 'これ',
    'replaced', 'replace', 'equipped', 'equip', 'following', 'every', 'number',
    'been', 'also', 'must', 'only', 'more', 'than', 'when', 'which', 'same',
    'above', 'below', 'both', 'either', 'other', 'another', 'additional',
    'maximum', 'cannot', 'card', 'profile', 'found', 'armoury', 'weapon',
    'weapons', 'these', 'those', 'taken', 'times', 'time', 'does', 'into',
  };

  /// Las habilidades de reglamento de una unidad: las líneas CORE y FACTION de la hoja impresa.
  ///
  /// El dataset las enlaza con `infoLinks` de tipo `rule`, que no son perfiles y por eso no
  /// aparecían en ninguna parte: Wazdakka Gutsmek salía sin Deep Strike, sin Lone Operative y sin
  /// Deadly Demise D3, que es lo que pasa cuando su moto explota.
  ///
  /// La X de «Deadly Demise X» la pone el enlace con un modifier sobre el nombre, no la regla: la
  /// regla es la misma para todos y cada unidad dice la suya.
  ///
  /// CORE o FACTION se decide por dónde vive la regla —el sistema de juego o el catálogo de la
  /// facción—, que es la misma separación que hace la hoja impresa y no hace falta escribirla.
  List<Ability> abilitiesOf(UnitEntry unit) {
    final cached = _abilityCache[unit.id];
    if (cached != null) return cached;
    final entry = node(unit.id);
    if (entry == null) return const [];

    final abilities = <String, Ability>{};
    final visited = <String>{};

    void collect(Map<String, dynamic> node_, int depth) {
      if (depth > 2) return;
      if (!visited.add(node_['id'] as String? ?? '')) return;
      if (enhancementIds.contains(node_['id'])) return;
      for (final raw in (node_['infoLinks'] as List? ?? const [])) {
        final link = raw as Map<String, dynamic>;
        if (link['type'] != 'rule') continue;
        final target = node(link['targetId'] as String? ?? '');
        if (target == null) continue;
        var name = target['name'] as String? ?? link['name'] as String? ?? '';
        // «Deadly Demise» + «D3». El valor va pegado con un espacio, como en la hoja.
        for (final modifier in Modifier.allOf(link)) {
          if (modifier.field == 'name' && modifier.type == 'append') {
            name = '$name ${modifier.value}'.trim();
          }
        }
        if (name.isEmpty) continue;
        abilities.putIfAbsent(
            name,
            () => Ability(
                  name: name,
                  description: target['description'] as String? ?? '',
                  kind: _esDelSistema(target['id'] as String? ?? '') ? 'core' : 'faction',
                ));
      }
      // Las de las miniaturas también: hay hojas que cuelgan Deep Strike de la miniatura.
      for (final child in _childLinks(node_)) {
        if (child.entry['type'] == 'model') collect(child.entry, depth + 1);
      }
    }

    collect(entry, 0);
    return _abilityCache[unit.id] = abilities.values.toList();
  }

  final Map<String, List<Ability>> _abilityCache = {};

  /// Si una regla la declara el sistema de juego, que es lo que la hace CORE.
  bool _esDelSistema(String id) => _idsDelSistema.contains(id);

  late final Set<String> _idsDelSistema = () {
    final ids = <String>{};
    for (final root in _roots) {
      if (root['type'] == 'catalogue') continue;
      for (final node_ in _descendants(root)) {
        final id = node_['id'];
        if (id is String) ids.add(id);
      }
    }
    return ids;
  }();

  /// La regla del reglamento que explica una palabra clave, si la hay.
  ///
  /// Las armas traen sus palabras entre corchetes —[SUSTAINED HITS 1], [LETHAL HITS], [BLAST]— y
  /// el jugador tiene que ir a buscarlas al reglamento. El número sobra para buscarla: la regla se
  /// llama «Sustained Hits» y el 1 es de esa arma.
  Rule? ruleNamed(String keyword) {
    final clave = _claveDeRegla(keyword);
    if (clave.isEmpty) return null;
    final exacta = _reglasPorClave[clave];
    if (exacta != null) return exacta;
    // Y si no casa entera, la regla cuyo nombre es el principio: «ANTI-INFANTRY 4+» es la regla
    // «Anti», y el resto es de esa arma. Se coge la más larga que encaje, para que «Feel No Pain»
    // no gane a «Feel No Pain 5+».
    Rule? mejor;
    var largo = 0;
    for (final entrada in _reglasPorClave.entries) {
      if (entrada.key.length <= largo) continue;
      if (!clave.startsWith(entrada.key)) continue;
      mejor = entrada.value;
      largo = entrada.key.length;
    }
    return mejor;
  }

  late final Map<String, Rule> _reglasPorClave = {
    for (final regla in coreRules) _claveDeRegla(regla.name): regla,
  };

  /// La clave con la que se casan «[SUSTAINED HITS 1]», «Sustained Hits» y «SUSTAINED HITS».
  ///
  /// Se quitan los corchetes, lo que va detrás de dos puntos —«LETHAL HITS: non-MONSTER» sigue
  /// siendo Lethal Hits— y todo lo que no sea una letra, que es donde viven el número del arma y
  /// el asterisco.
  static String _claveDeRegla(String texto) => texto
      .replaceAll(RegExp(r'[\[\]]'), '')
      .split(':')
      .first
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z]'), '');

  /// Cuántas miniaturas de la selección llevan cada perfil de arma.
  ///
  /// Es el número que la hoja impresa pone a la izquierda del arma: «4 Guardian spear». Sin él, una
  /// escuadra de cinco con dos armas distintas se lee como si todas llevaran las dos.
  ///
  /// La cuenta es la de la miniatura que la lleva, no la del arma: cuatro Custodian Guard con una
  /// lanza cada uno son cuatro lanzas, aunque cada arma esté puesta una sola vez.
  Map<String, int> weaponCountsOf(Selection selection) {
    final counts = <String, int>{};

    /// Las armas que hay en un nodo y en lo que cuelga de él, **sin repetir**.
    ///
    /// Sin lo de no repetir salen el doble: la miniatura enlaza el perfil del arma y además la
    /// lleva puesta como opción, así que el mismo Guardian Spear aparece en los dos sitios.
    Set<String> armasDe(Selection node_) {
      final nombres = <String>{};
      final entry = node(node_.entryId);
      if (entry != null) {
        for (final profile in profilesOf(entry)) {
          if (profile.typeName.contains('Weapons')) nombres.add(profile.name);
        }
      }
      for (final child in node_.children) {
        if (child.type == 'model') continue;
        nombres.addAll(armasDe(child));
      }
      return nombres;
    }

    void recorre(Selection node_, int portadores) {
      final cuantos = portadores * node_.count;
      final tieneMiniaturas = node_.children.any((c) => c.type == 'model');
      // Quien lleva el arma es la miniatura. Una unidad que se compone de miniaturas no lleva
      // nada ella: reparte. Una que no tiene ninguna —un vehículo— es ella la que lleva.
      if (!tieneMiniaturas) {
        for (final nombre in armasDe(node_)) {
          counts.update(nombre, (n) => n + cuantos, ifAbsent: () => cuantos);
        }
        return;
      }
      for (final child in node_.children) {
        if (child.type == 'model') recorre(child, cuantos);
      }
    }

    recorre(selection, 1);
    return counts;
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

/// A qué unidades puede unirse un líder o una unidad de apoyo, leído de su hoja de datos.
///
/// El dataset no lo modela: lo deja escrito en el texto de la habilidad «Leader» o «Support», y
/// de dos formas —seguidos por comas y en mayúsculas, o en viñetas con el nombre tal cual—. De los
/// 523 nombres que citan los 282 líderes, casan 517 con una unidad real, el 98 %.
///
/// Las dos clases son distintas y no se estorban: la regla 19.01 del reglamento dice que cada
/// unidad anfitriona puede llevar **un líder y una unidad de apoyo**, no uno de los dos.
extension Lideres on Dataset {
  static const _clases = ['Leader', 'Support'];


  /// `Leader`, `Support`, o `null` si no se une a nada.
  String? attachKind(UnitEntry unit) {
    for (final clase in _clases) {
      if (unit.keywords.contains(clase)) return clase;
    }
    return null;
  }

  /// Los nombres de unidad que cita su habilidad de unión.
  List<String> leaderTargetNames(UnitEntry unit) {
    // Con la hoja entera y no solo con los perfiles de la entrada: la habilidad cuelga muchas
    // veces de la miniatura y no de la unidad, un nivel más abajo.
    for (final perfil in sheetOf(unit)) {
      if (!_clases.contains(perfil.name)) continue;
      for (final valor in perfil.characteristics.values) {
        final cuerpo = valor.contains(':') ? valor.split(':').last : valor;
        // Con viñetas, cada viñeta es un nombre y va tal cual. Sin ellas, los nombres vienen en
        // mayúsculas y lo demás es prosa.
        final porVinetas = cuerpo.contains('■') || cuerpo.contains('•');
        return [
          for (final trozo in cuerpo.split(RegExp(r'[■•,\n]')))
            if (_pareceNombre(trozo.trim(), sueltoEnVineta: porVinetas)) trozo.trim(),
        ];
      }
    }
    return const [];
  }

  /// Las unidades de la facción a las que este líder se puede unir.
  List<UnitEntry> leaderTargets(Faction faction, UnitEntry leader) {
    final nombres = leaderTargetNames(leader).map(_plano).toSet();
    if (nombres.isEmpty) return const [];
    return [
      for (final u in faction.units)
        if (nombres.contains(_plano(u.name))) u,
    ];
  }

  /// Si se une a algo: lo dice su palabra clave, no el texto.
  bool isLeader(UnitEntry unit) => attachKind(unit) != null;

  /// Si puede unirse a una unidad que **ya lleve** otro de su clase.
  ///
  /// La regla general deja un líder y un apoyo por unidad, pero hay hojas que traen su excepción
  /// escrita: «puedes adjuntar esta miniatura a una de las unidades anteriores aunque ya se le
  /// haya adjuntado una miniatura Captain o Chapter Master». El Sanguinary Priest, el Castellan,
  /// el Crusade Ancient, Cato Sicarius, The Visarch, el Warlock y dos más lo dicen así.
  ///
  /// El dataset no lo modela en ninguna parte: está en el texto de la habilidad, igual que a quién
  /// se une. Se reconoce por la frase entera, no por «aunque» suelto, que aparece en habilidades
  /// que no hablan de esto.
  bool aceptaOtroLider(UnitEntry unit) {
    final cached = _excepcionCache[unit.id];
    if (cached != null) return cached;
    // En cualquier perfil, no solo en el de Leader o Support: hay hojas que lo dejan escrito en
    // una habilidad aparte. Y en los dos idiomas, porque la traducción no llega a todas.
    for (final perfil in sheetOf(unit)) {
      for (final valor in perfil.characteristics.values) {
        final texto = valor.toLowerCase();
        if (texto.contains('ya se le haya adjuntado') ||
            texto.contains('already been attached')) {
          return _excepcionCache[unit.id] = true;
        }
      }
    }
    return _excepcionCache[unit.id] = false;
  }
}

/// Sin viñetas el texto marca los nombres en mayúsculas; con viñetas, cada viñeta ya es un nombre.
bool _pareceNombre(String t, {required bool sueltoEnVineta}) {
  if (t.length < 4) return false;
  if (sueltoEnVineta) return !t.contains(RegExp(r'[.:]'));
  return RegExp(r"^[A-ZÁÉÍÓÚÜÑ0-9'’\- ()/]+$").hasMatch(t);
}

String _plano(String x) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final sinTildes = x.toLowerCase().split('').map((c) => tildes[c] ?? c).join();
  return sinTildes.replaceAll(RegExp(r'\[(legends|crucible)\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}
