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
