import 'dart:io';

import 'package:warorgan_core/warorgan_core.dart';

/// Audita el motor contra el dataset entero: qué resuelve, qué no, y qué se deja sin comprobar.
///
/// Es la respuesta a «¿está listo para montar la interfaz?». No mide si el código corre, que para
/// eso están las pruebas, sino **cuánto del dataset entiende**, que es lo que decide si la app
/// puede enseñar una lista y fiarse de ella.
///
/// ```bash
/// dart run bin/auditoria.dart [directorio]
/// ```
void main(List<String> args) async {
  final directory = Directory(args.isNotEmpty
      ? args.first
      : (Directory('../data/bsdata-es').existsSync() ? '../data/bsdata-es' : '../data/bsdata'));
  final dataset = await Dataset.load(directory);
  print('Dataset: ${directory.path}  ·  ${dataset.nodeCount} nodos\n');

  final factions = dataset.factions;
  final battleSizes = dataset.battleSizes;
  final strikeForce = battleSizes.firstWhere((b) => b.pointsLimit == 2000);

  var units = 0, withPoints = 0, options = 0;
  var detachments = 0, boardingActions = 0, withEnhancements = 0, fullSized = 0, withFour = 0;
  var skippedCosts = 0, unitsWithSkippedCosts = 0;
  var uncheckedConstraints = 0, unitsWithUnchecked = 0;
  var needingChoices = 0;
  var offered = 0, offeredOptions = 0, unresolvedVisibility = 0;
  final factionsWithoutDetachments = <String>[];

  for (final faction in factions) {
    final ofFaction = dataset.detachmentsOf(faction);
    if (ofFaction.isEmpty) factionsWithoutDetachments.add(faction.name);
    detachments += ofFaction.length;
    boardingActions += dataset.detachmentsOf(faction, boardingActions: true).length;
    for (final detachment in ofFaction) {
      final enhancements = dataset.enhancementsOf(faction, detachmentId: detachment.id);
      if (enhancements.isNotEmpty) withEnhancements++;
      if (detachment.detachmentPoints >= 2) {
        fullSized++;
        if (enhancements.length == 4) withFour++;
      }
    }

    if (ofFaction.isNotEmpty) {
      final visible = Roster(faction: faction, pointsLimit: 2000)
        ..battleSize = strikeForce
        ..detachments.add(ofFaction.first);
      for (final unit in visible.availableUnits) {
        offered++;
        offeredOptions += visible.optionsFor(visible.selectionFor(unit)).length;
      }
      unresolvedVisibility += visible.unresolvedVisibility;
    }

    for (final unit in faction.units) {
      units++;
      if (unit.points != null) withPoints++;

      final selection = dataset.selectionFor(unit);
      options += dataset.optionsFor(selection).length;

      final roster = Roster(faction: faction, pointsLimit: 2000)
        ..battleSize = strikeForce
        ..add(selection);
      if (ofFaction.isNotEmpty) roster.detachments.add(ofFaction.first);
      if (roster.validate().isNotEmpty) needingChoices++;

      skippedCosts += roster.skippedModifiers;
      if (roster.skippedModifiers > 0) unitsWithSkippedCosts++;
      uncheckedConstraints += roster.uncheckedConstraints;
      if (roster.uncheckedConstraints > 0) unitsWithUnchecked++;
    }
  }

  String percent(num part, num whole) =>
      whole == 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)} %';

  print('LO QUE RESUELVE');
  print('  facciones jugables            ${factions.length}');
  print('  unidades                      $units  ·  con puntos $withPoints '
      '(${percent(withPoints, units)})');
  print('  opciones que una unidad ofrece $offeredOptions de $options'
      '  ·  el resto son de otra unidad que comparte la lista');
  print('  unidades que una lista ofrece $offered de $units (${percent(offered, units)})'
      '  ·  el resto son Legends, aliados o piden otro detachment');
  print('  detachments jugables          $detachments'
      '  ·  de Boarding Actions $boardingActions');
  print('  tamaños de partida            ${battleSizes.map((b) => b.pointsLimit).join(', ')}');
  print('  tipos de fuerza               ${dataset.forces.map((f) => f.name).join(', ')}');
  print('');
  print('MEJORAS');
  print('  detachments con mejoras       $withEnhancements de $detachments '
      '(${percent(withEnhancements, detachments)})');
  print('  de tamaño completo con 4      $withFour de $fullSized '
      '(${percent(withFour, fullSized)})');
  print('');
  print('  piden elegir algo al añadirse   $needingChoices de $units '
      '(${percent(needingChoices, units)})  ·  un arma, un tamaño de escuadra');
  print('');
  print('LO QUE NO EVALÚA  (se deja sin aplicar, nunca se inventa)');
  print('  modifiers de coste            $skippedCosts, en $unitsWithSkippedCosts unidades '
      '(${percent(unitsWithSkippedCosts, units)})');
  print('  restricciones sin comprobar   $uncheckedConstraints, en $unitsWithUnchecked unidades '
      '(${percent(unitsWithUnchecked, units)})');
  print('  visibilidad sin evaluar       $unresolvedVisibility'
      '  ·  puede dejar alguna unidad de más en el selector');
  if (factionsWithoutDetachments.isNotEmpty) {
    print('  facciones sin detachments     ${factionsWithoutDetachments.join(', ')}');
  }
}
