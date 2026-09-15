import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final dataset = await Dataset.load(_dir());
  for (final fn in ['Chaos - Chaos Space Marines','Chaos - Death Guard','Chaos - World Eaters']) {
    final f = dataset.factionNamed(fn);
    final u = f.units.where((x)=>x.name=='Defiler').firstOrNull;
    if (u==null) continue;
    for (final d in dataset.detachmentsOf(f)) {
      final r = Roster(faction: f, pointsLimit: 3000)..detachments.add(d);
      final s = r.selectionFor(u); r.add(s);
      final avisos = r.validate().map((v)=>v.message).toList();
      final puestas = s.children.map((c)=>c.name).toList();
      print('${fn.split(' - ').last.padRight(20)} ${d.name.padRight(26)} '
          '${avisos.isEmpty ? "sin avisos" : avisos.join(" | ")}');
      if (avisos.any((a)=>a.toLowerCase().contains('baleflamer'))) {
        print('     !!! equipo puesto: $puestas');
      }
    }
  }
}
