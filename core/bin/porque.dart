import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main(List<String> args) async {
  final dataset = await Dataset.load(_dir());
  final f = dataset.factionNamed(args[0]);
  final roster = Roster(faction: f, pointsLimit: 2000)
    ..detachments.add(dataset.detachmentsOf(f).first);
  final u = roster.selectionFor(f.units.firstWhere((x) => x.name == args[1]));
  roster.add(u);
  final crudas = dataset.optionsFor(u);
  final filtradas = roster.optionsFor(u).map((o) => o.entryId).toSet();
  print('=== ${args[1]} (${f.name}) ===');
  print('el dataset ofrece ${crudas.length}, la lista deja ${filtradas.length}');
  for (final o in crudas) {
    if (!filtradas.contains(o.entryId)) {
      print('   ESCONDIDA: ${o.name}  (grupo: ${o.groupName})');
    }
  }
}
