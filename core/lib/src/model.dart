import 'dataset.dart';
import 'modifiers.dart';
import 'topes.dart';

/// Un perfil del dataset: una habilidad, un arma o la línea de características de una unidad.
///
/// Es donde vive el texto que lee el jugador, ya traducido: la clave `Description` de
/// [characteristics] contiene la explicación en español.
class Profile {
  Profile({required this.name, required this.typeName, required this.characteristics});

  final String name;
  final String typeName;
  final Map<String, String> characteristics;

  /// El texto explicativo del perfil, si lo tiene.
  String? get description => characteristics['Description'];

  factory Profile.fromNode(Map<String, dynamic> node) {
    final characteristics = <String, String>{};
    for (final raw in (node['characteristics'] as List? ?? const [])) {
      final characteristic = raw as Map<String, dynamic>;
      final name = characteristic['name'] as String?;
      final text = characteristic[r'$text'] as String?;
      if (name != null && text != null) characteristics[name] = text;
    }
    return Profile(
      name: node['name'] as String? ?? '',
      typeName: node['typeName'] as String? ?? '',
      characteristics: characteristics,
    );
  }
}

/// Una restricción de legalidad tal y como la declara BattleScribe.
///
/// [field] dice sobre qué se cuenta: `selections` para el número de selecciones, o el id de un
/// tipo de coste (por ejemplo Enhancements) para limitar ese coste. [scope] dice contra qué se
/// compara: la propia entrada, su padre, el destacamento, el roster entero.
///
/// [value] es el número **declarado**, que no siempre es el que vale: hay modifiers que lo cambian
/// según el tamaño de la partida o lo que haya en la lista. El efectivo lo calcula el roster.
class Constraint {
  Constraint({
    required this.id,
    required this.type,
    required this.field,
    required this.scope,
    required this.value,
    required this.includeChildSelections,
    this.message,
    this.childId,
    this.traverseAssociationGroup = false,
  });

  /// Identificador de la restricción. Es lo que apunta un modifier que la cambia.
  final String id;

  /// Qué se cuenta, cuando la restricción no cuenta la propia opción: en las de `associations`,
  /// la categoría de lo que se une —Leader, Support—, o nada, que es «cualquier unión».
  final String? childId;

  /// Si se cuenta sobre la **unidad unida** entera —la anfitriona y sus líderes— y no sobre la
  /// selección sola. Es como BSData dice «una unidad unida solo puede llevar 1 mejora».
  final bool traverseAssociationGroup;

  final String type; // min | max
  final String field;
  final String scope; // self | parent | force | roster | root-entry
  final num value;
  final bool includeChildSelections;

  /// Mensaje de error que trae el propio dataset, cuando lo trae.
  final String? message;

  bool get isMax => type == 'max';

  factory Constraint.fromNode(Map<String, dynamic> node) => Constraint(
        id: node['id'] as String? ?? '',
        type: node['type'] as String? ?? '',
        field: node['field'] as String? ?? '',
        scope: node['scope'] as String? ?? '',
        value: node['value'] as num? ?? 0,
        includeChildSelections: node['includeChildSelections'] as bool? ?? false,
        message: node['message'] as String?,
        childId: node['childId'] as String?,
        traverseAssociationGroup: node['traverseAssociationGroup'] as bool? ?? false,
      );
}

/// A qué se puede unir un personaje, tal como lo escribe BSData.
///
/// «Leading» o «Supporting», con `action: group`: el personaje se une a una unidad y juegan como
/// una sola. Las condiciones se preguntan a la unidad candidata —«¿eres Plague Marines?»—, salvo
/// las que llevan `queryFromSelf`, que se preguntan al personaje.
class Association {
  Association({
    required this.id,
    required this.name,
    required this.childId,
    required this.min,
    required this.max,
    required this.conditions,
    required this.conditionGroups,
  });

  final String id;

  /// `Leading`, `Supporting`, `Support Weapon`…
  final String name;

  /// Qué se puede unir: `unit` o `model`.
  final String childId;

  /// Con `min` 1 el personaje **tiene** que ir unido a algo.
  final int min;

  /// A cuántas unidades puede unirse. En todo el dataset es una.
  final int max;
  final List<Condition> conditions;
  final List<ConditionGroup> conditionGroups;

  bool get isSupporting => name == 'Supporting';

  /// Si la unidad candidata cumple las condiciones, contestando cada una con [test].
  bool acceptsWith(bool Function(Condition) test) =>
      conditions.every(test) && conditionGroups.every((g) => g.evaluate(test));

  /// Si se saben contestar todas sus condiciones.
  bool isSupportedWith(bool Function(Condition) supports) =>
      conditions.every(supports) && conditionGroups.every((g) => g.isSupportedWith(supports));

  factory Association.fromNode(Map<String, dynamic> node) => Association(
        id: node['id'] as String? ?? '',
        name: node['name'] as String? ?? '',
        childId: node['childId'] as String? ?? 'unit',
        min: (node['min'] as num?)?.round() ?? 0,
        max: (node['max'] as num?)?.round() ?? 1,
        conditions: [
          for (final raw in (node['conditions'] as List? ?? const []))
            Condition.fromNode(raw as Map<String, dynamic>),
        ],
        conditionGroups: [
          for (final raw in (node['conditionGroups'] as List? ?? const []))
            ConditionGroup.fromNode(raw as Map<String, dynamic>),
        ],
      );
}

/// Una unidad seleccionable de una facción.
class UnitEntry {
  UnitEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.role,
    required this.keywords,
    required this.points,
    required this.profiles,
    required this.constraints,
    this.visibility = const [],
    this.categoryModifiers = const [],
  });

  final String id;
  final String name;

  /// `unit` o `model`.
  final String type;

  /// El rol principal en la lista, de la categoría marcada como `primary`.
  final String? role;

  final List<String> keywords;

  /// Puntos de la configuración base.
  ///
  /// Es el coste declarado en la propia unidad o, si no lo declara, el de la miniatura que cuelga
  /// de ella. **No es el coste final**: en el roster el coste es la suma de todo lo seleccionado,
  /// y eso depende de las opciones que elija el jugador. Es `null` en las unidades que no llevan
  /// puntos, que las hay: las gratuitas y el contenido Legends.
  final int? points;

  final List<Profile> profiles;
  final List<Constraint> constraints;

  /// Los modifiers que deciden si esta unidad se le puede ofrecer a una lista concreta.
  ///
  /// El dataset esconde muchísimo con ellos: las unidades Legends, los aliados, los Imperial
  /// Agents y los demonios que solo entran con según qué detachment. Aquí solo viajan; quien sabe
  /// evaluarlos es el roster, que es el único que conoce la configuración de la lista.
  final List<Modifier> visibility;

  /// Los modifiers que le cambian las categorías, y con ellas el rol con el que se agrupa.
  ///
  /// Es como el dataset marca a los aliados: un War Dog lleva un `set-primary` a la categoría
  /// «Allies: Chaos Knights» condicionado a que el catálogo principal **no** sea el suyo. En una
  /// lista de Death Guard ese modifier se cumple y su rol deja de ser Character. Aquí solo viajan;
  /// quien sabe evaluarlos es el roster, que es el que conoce de qué facción es la lista.
  final List<Modifier> categoryModifiers;

  /// Las habilidades de la unidad, que son los perfiles con texto explicativo.
  Iterable<Profile> get abilities => profiles.where((p) => p.description != null);

  /// «Por cada 5 miniaturas, 1 arma», leído de la frase impresa de la hoja.
  ///
  /// Lo rellena el dataset al cargar, porque es lo único que sabe leer las notas. El roster lo usa
  /// para calcular el techo de verdad de cada arma: BSData deja muchos techos puestos al valor de
  /// la escuadra llena, y con media escuadra decía que cabían el doble de armas especiales de las
  /// que caben. Ver `topes.dart`.
  List<TopePorMiniaturas> topesImpresos = const [];
}

/// Una regla del reglamento básico, ya traducida.
///
/// Son las que explican las palabras clave que aparecen entre corchetes en las armas y en las
/// habilidades —[SUSTAINED HITS], [DEVASTATING WOUNDS], [ANTI-INFANTRY 4+]— y que el jugador tiene
/// que buscar en el reglamento. Es lo que alimenta la pestaña Wiki.
class Rule {
  Rule({required this.id, required this.name, required this.description});

  final String id;
  final String name;
  final String description;
}

/// Un tipo de fuerza: la clase de lista que se está construyendo.
///
/// El sistema declara cuatro —Army Roster, Boarding Actions, Crusade Force y Crusade Army— y una
/// lista es de uno y solo uno. Importa porque hay reglas que solo valen en algunos: los Poxwalkers
/// se pueden repetir tres veces en una lista normal y seis en una de Crusade.
class Force {
  Force({required this.id, required this.name, required this.node});

  final String id;
  final String name;

  /// El nodo del dataset. Lleva las reglas de ejército: el límite de puntos, el presupuesto de
  /// Detachment Points y cuántas Enhancements caben.
  final Map<String, dynamic> node;

  List<Constraint> get constraints => [
        for (final raw in (node['constraints'] as List? ?? const []))
          Constraint.fromNode(raw as Map<String, dynamic>),
      ];

  /// Los roles de batalla, en el orden en que la fuerza los declara.
  ///
  /// Es el orden de la hoja de ejército —Epic Hero, Character, Battleline, Infantry…— y no hace
  /// falta escribirlo a mano: lo dice el dataset. Agrupar por aquí es lo que evita tener que
  /// buscar una unidad en una lista plana de cientos.
  List<({String id, String name})> get roles => [
        for (final raw in (node['categoryLinks'] as List? ?? const []))
          if ((raw as Map<String, dynamic>)['targetId'] is String &&
              raw['name'] is String &&
              raw['name'] != 'Configuration')
            (id: raw['targetId'] as String, name: raw['name'] as String),
      ];
}

/// El tamaño de la partida, que el dataset llama Battle Size.
///
/// No es decorativo: **cambia los límites de la lista**. Muchas unidades se pueden repetir tres
/// veces en Strike Force y solo dos en Incursion, y quien lo decide es un modifier sobre la
/// restricción que mira qué tamaño se ha elegido.
class BattleSize {
  BattleSize({required this.id, required this.name, required this.pointsLimit});

  final String id;
  final String name;

  /// El límite de puntos que el propio dataset asocia a este tamaño.
  final int pointsLimit;
}

/// Una facción jugable.
class Faction {
  Faction(this.dataset, this.node);

  final Dataset dataset;
  final Map<String, dynamic> node;

  String get id => node['id'] as String? ?? '';
  String get name => node['name'] as String? ?? '';

  /// Las unidades que el jugador puede meter en una lista de esta facción.
  ///
  /// Incluye las que la facción hereda de los catálogos que enlaza: sin eso, los capítulos de
  /// Space Marines no tendrían ninguna unidad propia.
  List<UnitEntry> get units => dataset.unitsOf(this);
}

/// La salvación invulnerable de una unidad, y contra qué vale.
///
/// No es una característica más de la línea: el dataset la deja como una habilidad con el número
/// en el nombre —«Invulnerable Save (5+\*)»— o solo en el texto, y **no siempre vale contra todo**.
/// Los Rangers la tienen de 5+ solo contra ataques a distancia y las Howling Banshees de 4+ solo
/// en cuerpo a cuerpo; los Knights, de uno y otro bando, están llenos de estas. El asterisco del
/// nombre es justo lo que avisa de que hay una condición, y sin leer el texto no se sabe cuál.
///
/// Enseñarla como un número suelto al lado de la salvación normal sería mentir en 521 de las 632
/// unidades que la tienen.
class Invulnerable {
  Invulnerable({required this.value, this.scope});

  /// El número, tal y como se tira: «4+».
  final String value;

  /// Contra qué vale, si no vale contra todo: `distancia` o `cuerpo a cuerpo`.
  final String? scope;

  bool get isConditional => scope != null;

  static final _number = RegExp(r'(\d\+)');

  /// La salvación invulnerable que declaran estos perfiles, si declaran alguna.
  static Invulnerable? of(Iterable<Profile> profiles) {
    for (final profile in profiles) {
      if (!profile.name.toLowerCase().contains('invulnerable')) continue;
      final text = profile.description ?? profile.characteristics.values.join(' ');
      final value = _number.firstMatch(profile.name)?.group(1) ??
          _number.firstMatch(text)?.group(1);
      if (value == null) continue;
      final lower = text.toLowerCase();
      // El texto ya viene traducido, así que se busca en español; el inglés queda por si el
      // dataset llega sin traducir, que es como corren los tests contra el original.
      final ranged = lower.contains('a distancia') || lower.contains('ranged attacks');
      final melee = lower.contains('cuerpo a cuerpo') || lower.contains('melee attacks');
      return Invulnerable(
        value: value,
        scope: ranged && !melee
            ? 'ataques a distancia'
            : melee && !ranged
                ? 'ataques de cuerpo a cuerpo'
                : null,
      );
    }
    return null;
  }
}

/// Una habilidad de una unidad que no es un perfil sino una **regla** del reglamento.
///
/// El dataset las enlaza con `infoLinks` de tipo `rule`, que es una cosa distinta de los perfiles
/// y por eso no salían en ninguna parte: Deep Strike, Lone Operative, Deadly Demise, Waaagh!. Son
/// las que la hoja impresa pone arriba del todo en una línea, y sin ellas no se sabe si una
/// unidad puede hacer despliegue rápido ni qué pasa cuando un tanque explota.
///
/// [kind] dice en qué línea va, y sale de dónde vive la regla: las que declara el sistema de juego
/// son CORE y las que declara el catálogo de la facción son FACTION. No hay que escribir ninguna
/// lista: es la misma separación que hace la hoja impresa.
class Ability {
  Ability({required this.name, required this.description, required this.kind});

  final String name;
  final String description;

  /// `core`, `faction` o `unit`.
  final String kind;

  bool get isCore => kind == 'core';
  bool get isFaction => kind == 'faction';
}
