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

  for (final unit in units.take(5)) {
    final points = unit.points == null ? 'sin puntos' : '${unit.points} pts';
    print('  ${unit.name}  ·  $points  ·  ${unit.role ?? 'sin rol'}');
    final ability = unit.abilities.isEmpty ? null : unit.abilities.first;
    if (ability != null) {
      final text = ability.description!.replaceAll('\n', ' ');
      print('      ${ability.name}: ${text.length > 100 ? '${text.substring(0, 100)}…' : text}');
    }
  }

  // Una lista de ejemplo, para ver el coste y la validación funcionando.
  final roster = Roster(faction: chosen, pointsLimit: 500, name: 'Ejemplo');
  for (final unit in units.where((u) => u.points != null).take(3)) {
    roster.add(dataset.selectionFor(unit));
  }
  print('');
  print('${roster.name}: ${roster.points}/${roster.pointsLimit} pts '
      '(quedan ${roster.pointsRemaining})');
  for (final unit in roster.units) {
    final detail = unit.children.isEmpty
        ? ''
        : '  (${unit.children.map((c) => '${c.count}× ${c.name}').join(', ')})';
    print('  ${unit.name}  ${unit.points} pts$detail');
  }
  final violations = roster.validate();
  if (violations.isEmpty) {
    print('  Lista legal');
  } else {
    for (final violation in violations) {
      print('  Incumple · $violation');
    }
  }
}
