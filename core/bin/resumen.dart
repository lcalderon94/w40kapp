import 'dart:io';

import 'package:warorgan_core/warorgan_core.dart';

/// Vuelca lo que la capa de datos resuelve del dataset, para verlo funcionando sin interfaz.
///
///     dart run bin/resumen.dart [ruta-al-dataset] [facción]
Future<void> main(List<String> args) async {
  final directory = Directory(args.isNotEmpty ? args[0] : '../data/bsdata-es');
  if (!directory.existsSync()) {
    stderr.writeln('No existe el dataset en ${directory.path}. '
        'Genéralo con: mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=apply');
    exit(1);
  }

  final dataset = await Dataset.load(directory);
  final factions = dataset.factions;
  print('Dataset            ${directory.path}');
  print('Identificadores    ${dataset.nodeCount}');
  print('Facciones          ${factions.length}');
  print('');

  final chosen = args.length > 1
      ? dataset.factionNamed(args[1])
      : factions.firstWhere((f) => f.name.contains('Death Guard'));
  final units = chosen.units;
  final withPoints = units.where((u) => u.points != null).length;
  print('${chosen.name}: ${units.length} unidades, $withPoints con puntos');
  print('');

  for (final unit in units.take(8)) {
    final points = unit.points == null ? 'sin puntos' : '${unit.points} pts';
    print('  ${unit.name}  ·  $points  ·  ${unit.role ?? 'sin rol'}');
    final ability = unit.abilities.isEmpty ? null : unit.abilities.first;
    if (ability != null) {
      final text = ability.description!.replaceAll('\n', ' ');
      print('      ${ability.name}: ${text.length > 110 ? '${text.substring(0, 110)}…' : text}');
    }
  }
}
