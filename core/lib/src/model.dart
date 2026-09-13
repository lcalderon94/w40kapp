import 'dataset.dart';

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
class Constraint {
  Constraint({
    required this.type,
    required this.field,
    required this.scope,
    required this.value,
    required this.includeChildSelections,
    this.message,
  });

  final String type; // min | max
  final String field;
  final String scope; // self | parent | force | roster | root-entry
  final num value;
  final bool includeChildSelections;

  /// Mensaje de error que trae el propio dataset, cuando lo trae.
  final String? message;

  bool get isMax => type == 'max';

  factory Constraint.fromNode(Map<String, dynamic> node) => Constraint(
        type: node['type'] as String? ?? '',
        field: node['field'] as String? ?? '',
        scope: node['scope'] as String? ?? '',
        value: node['value'] as num? ?? 0,
        includeChildSelections: node['includeChildSelections'] as bool? ?? false,
        message: node['message'] as String?,
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

  /// Las habilidades de la unidad, que son los perfiles con texto explicativo.
  Iterable<Profile> get abilities => profiles.where((p) => p.description != null);
}

/// Una facción jugable.
class Faction {
  Faction(this._dataset, this.node);

  final Dataset _dataset;
  final Map<String, dynamic> node;

  String get id => node['id'] as String? ?? '';
  String get name => node['name'] as String? ?? '';

  /// Las unidades que el jugador puede meter en una lista de esta facción.
  ///
  /// Incluye las que la facción hereda de los catálogos que enlaza: sin eso, los capítulos de
  /// Space Marines no tendrían ninguna unidad propia.
  List<UnitEntry> get units => _dataset.unitsOf(this);
}
