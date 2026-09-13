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
  /// Cuelgan de la entrada de configuración, en un grupo llamado `Detachment` que unas facciones
  /// llevan incrustado y otras enlazan a un grupo compartido.
  List<Detachment> detachmentsOf(Faction faction) {
    final detachments = <Detachment>[];
    final seen = <String>{};
    for (final link in _rootLinks(faction.node)) {
      final entry = node(link['targetId'] as String? ?? '');
      if (entry == null || !_isConfiguration(entry)) continue;
      for (final group in _groupsOf(entry)) {
        if (group['name'] != 'Detachment') continue;
        for (final option in _childEntries(group)) {
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
          ));
        }
      }
    }
    return detachments;
  }

  /// Las mejoras que habilita un detachment, con su texto ya traducido.
  ///
  /// Una mejora se reconoce por llevar coste del tipo Enhancements, no por el nombre de su grupo,
  /// que cambia de una facción a otra. Se le atribuye a un detachment cuando ella o el grupo que la
  /// contiene se esconden con un modifier que nombra a ese detachment.
  ///
  /// Es un criterio que se queda corto antes que inventarse nada: si devuelve una mejora, es de ese
  /// detachment, pero hay detachments cuyas mejoras no se localizan porque el dataset las engancha
  /// por la unidad que puede llevarlas en vez de por el detachment. Ver [enhancementCoverage].
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

  static const _enhancementCostTypeId = 'f759-1bc4-cb3a-f0d2';

  static bool _isEnhancement(Map<String, dynamic> entry) =>
      (entry['costs'] as List? ?? const []).any((raw) =>
          (raw as Map<String, dynamic>)['typeId'] == _enhancementCostTypeId &&
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

  static bool _isConfiguration(Map<String, dynamic> entry) =>
      (entry['categoryLinks'] as List? ?? const []).any((raw) =>
          (raw as Map<String, dynamic>)['primary'] == true && raw['name'] == 'Configuration');

  /// Los grupos de opciones de un nodo, estén incrustados o lleguen por enlace.
  Iterable<Map<String, dynamic>> _groupsOf(Map<String, dynamic> node_) sync* {
    for (final raw in (node_['selectionEntryGroups'] as List? ?? const [])) {
      yield raw as Map<String, dynamic>;
    }
    for (final raw in (node_['entryLinks'] as List? ?? const [])) {
      final link = raw as Map<String, dynamic>;
      if (link['type'] != 'selectionEntryGroup') continue;
      final target = node(link['targetId'] as String? ?? '');
      if (target != null) yield target;
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
      basePointsEach: _points(entry) ?? 0,
      count: count,
      groupId: groupId,
      groupName: groupName,
      constraints: constraints,
      groupConstraints: groupConstraints,
      modifiers: Modifier.allOf(entry),
      categoryIds: [
        for (final raw in (entry['categoryLinks'] as List? ?? const []))
          if ((raw as Map<String, dynamic>)['targetId'] is String) raw['targetId'] as String,
      ],
    );

    for (final child in _childEntries(entry)) {
      final minimum = _minimumSelections(child);
      if (minimum > 0) {
        selection.addChild(_selectionFrom(child,
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
          selection.addChild(_selectionFrom(option,
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
