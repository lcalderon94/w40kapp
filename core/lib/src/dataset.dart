import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'roster.dart';

/// El dataset de BattleScribe ya traducido, cargado y resuelto.
///
/// Los 46 ficheros no son independientes: se referencian entre ellos por identificador, así que
/// hay que indexarlos todos juntos antes de poder resolver nada. Una facción cargada por su cuenta
/// no puede listar sus unidades.
class Dataset {
  Dataset._(this._nodesById, this._roots);

  /// Identificador del tipo de coste en puntos, declarado en el fichero del sistema de juego.
  static const pointsCostTypeId = '51b2-306e-1021-d207';

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

    final nodesById = <String, Map<String, dynamic>>{};
    final roots = <Map<String, dynamic>>[];
    for (final file in files) {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final root = decoded.values.first as Map<String, dynamic>;
      roots.add(root);
      _index(decoded, nodesById);
    }
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
    final seenCatalogues = <String>{};
    final seenEntries = <String>{};

    void collect(Map<String, dynamic> catalogue) {
      if (!seenCatalogues.add(catalogue['id'] as String? ?? '')) return;
      for (final raw in (catalogue['entryLinks'] as List? ?? const [])) {
        final target = node((raw as Map<String, dynamic>)['targetId'] as String? ?? '');
        if (target == null) continue;
        if (target['type'] != 'unit' && target['type'] != 'model') continue;
        if (!seenEntries.add(target['id'] as String? ?? '')) continue;
        units.add(_toUnit(target));
      }
      for (final raw in (catalogue['catalogueLinks'] as List? ?? const [])) {
        final link = raw as Map<String, dynamic>;
        if (link['importRootEntries'] != true) continue;
        final target = node(link['targetId'] as String? ?? '');
        if (target != null) collect(target);
      }
    }

    collect(faction.node);
    return units;
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

  Selection _selectionFrom(
    Map<String, dynamic> entry, {
    required String? groupId,
    required String? groupName,
    required List<Constraint> groupConstraints,
    int count = 1,
  }) {
    final constraints = [
      for (final raw in (entry['constraints'] as List? ?? const []))
        Constraint.fromNode(raw as Map<String, dynamic>),
    ];
    final selection = Selection(
      entryId: entry['id'] as String? ?? '',
      name: entry['name'] as String? ?? '',
      type: entry['type'] as String? ?? '',
      pointsEach: _points(entry) ?? 0,
      count: count,
      groupId: groupId,
      groupName: groupName,
      constraints: constraints,
      groupConstraints: groupConstraints,
    );

    for (final child in _childEntries(entry)) {
      final minimum = _minimumSelections(child);
      if (minimum > 0) {
        selection.children.add(_selectionFrom(child,
            groupId: null, groupName: null, groupConstraints: const [], count: minimum));
      }
    }

    for (final raw in (entry['selectionEntryGroups'] as List? ?? const [])) {
      final group = raw as Map<String, dynamic>;
      final groupRules = [
        for (final c in (group['constraints'] as List? ?? const []))
          Constraint.fromNode(c as Map<String, dynamic>),
      ];
      for (final option in _childEntries(group)) {
        final minimum = _minimumSelections(option);
        if (minimum > 0) {
          selection.children.add(_selectionFrom(option,
              groupId: group['id'] as String?,
              groupName: group['name'] as String?,
              groupConstraints: groupRules,
              count: minimum));
        }
      }
    }

    return selection;
  }

  /// Las entradas hijas de un nodo, estén incrustadas o lleguen por enlace.
  Iterable<Map<String, dynamic>> _childEntries(Map<String, dynamic> node_) sync* {
    for (final raw in (node_['selectionEntries'] as List? ?? const [])) {
      yield raw as Map<String, dynamic>;
    }
    for (final raw in (node_['entryLinks'] as List? ?? const [])) {
      final target = node((raw as Map<String, dynamic>)['targetId'] as String? ?? '');
      if (target != null) yield target;
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
