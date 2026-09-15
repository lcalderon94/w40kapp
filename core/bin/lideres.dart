// Cuántos líderes resuelven sus objetivos, en las 36 facciones.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final dataset = await Dataset.load(_dir());
  var lideres=0, conObjetivos=0, objetivos=0;
  final sinResolver = <String>[];
  for (final f in dataset.factions) {
    for (final u in f.units) {
      if (!dataset.isLeader(u)) continue;
      lideres++;
      final t = dataset.leaderTargets(f, u);
      if (t.isNotEmpty) { conObjetivos++; objetivos += t.length; }
      else if (dataset.leaderTargetNames(u).isNotEmpty && sinResolver.length < 6) {
        sinResolver.add('${f.name.split(' - ').last} · ${u.name} → ${dataset.leaderTargetNames(u)}');
      }
    }
  }
  print('líderes en las ${dataset.factions.length} facciones: $lideres');
  print('con objetivos resueltos: $conObjetivos  ($objetivos uniones posibles)');
  print('con texto pero sin resolver: ${sinResolver.length}');
  for (final s in sinResolver) print('   $s');
}
