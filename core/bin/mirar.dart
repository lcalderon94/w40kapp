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
  roster.applyModifiers();
  print('=== ${args[1]} · ${u.points} pts ===');
  ver(roster, u, 0);
  print('avisos:');
  for (final v in roster.validate()) {
    print('   - ${v.message}');
  }
}

void ver(Roster roster, Selection s, int n) {
  final pad = '  ' * n;
  print('$pad[puesto] ${s.name} x${s.count}');
  for (final g in s.groups) {
    final uso = roster.groupUsage(s, g);
    print('$pad  grupo «${g.name}» min=${uso.minimo} max=${uso.maximo} puestas=${uso.puestas}'
        '${g.parentId != null ? " (dentro de otro)" : ""}');
  }
  for (final o in roster.optionsFor(s)) {
    final max = o.constraints
        .where((c) => c.isMax && c.field == 'selections')
        .map((c) => c.value.round())
        .join(',');
    print('$pad  ofrece: ${o.name}  grupo=${o.groupName}  maxPropio=${max.isEmpty ? "-" : max}');
  }
  for (final h in s.children) {
    ver(roster, h, n + 1);
  }
}
