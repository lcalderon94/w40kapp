// Los precios de una facción tal y como los calcula el motor, para contrastarlos con el MFM.
import 'dart:convert';
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main(List<String> args) async {
  final dataset = await Dataset.load(_dir());
  final f = dataset.factionNamed(args[0]);
  final roster = Roster(faction: f, pointsLimit: 3000)
    ..detachments.add(dataset.detachmentsOf(f).first);
  final salida = [];
  for (final u in f.units) {
    final s = roster.selectionFor(u);
    roster.units
      ..clear()
      ..add(s);
    roster.applyModifiers();
    final minis = s.descendantsAndSelf
        .where((x) => x.type == 'model')
        .fold<int>(0, (t, x) => t + x.count);
    salida.add({'nombre': u.name, 'minis': minis, 'pts': s.points});
  }
  print(jsonEncode(salida));
}
