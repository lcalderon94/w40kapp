import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final e=Directory('../data/bsdata-es');return e.existsSync()?e:Directory('../data/bsdata');}
void main() async {
  final ds = await Dataset.load(_dir(), notas: File('../data/wargear/notas-de-equipo.json'));
  final f = ds.factionNamed('Chaos - Death Guard');
  final r = Roster(faction: f, pointsLimit: 2000)..battleSize = ds.battleSizes.firstWhere((b)=>b.pointsLimit==2000);
  final d = ds.detachmentsOf(f); if (d.isNotEmpty) r.detachments.add(d.first);
  final u = r.selectionFor(f.units.firstWhere((x)=>x.name=='Biologus Putrifier'));
  r.add(u); r.applyModifiers();
  print('hijos: ${u.children.map((c)=>"${c.name}x${c.count}(grupo=${c.groupId})").toList()}');
  print('grupos: ${u.groups.map((g)=>"${g.name}(id=${g.id},padre=${g.parentId})").toList()}');
  final ofrecidas = r.optionsFor(u);
  print('ofrece: ${ofrecidas.map((o)=>"${o.name}(grupo=${o.groupId})").toList()}');
  for (final c in u.children) {
    print('hijo "${c.name}" esFijo=${r.isFixed(u, c, hayAlternativas: ofrecidas.where((o)=>o.groupId==c.groupId).length>1)} groups=${c.groups.length} opciones=${r.optionsFor(c).length}');
  }
  final wargear = u.groups.firstWhere((g)=>g.name=='Wargear');
  final uso = r.groupUsage(u, wargear);
  print('grupo Wargear min=${uso.minimo} max=${uso.maximo} puestas=${uso.puestas}');
  for (final c in wargear.constraints) print('  constraint ${c.isMax?"max":"min"} scope=${c.scope} value=${c.value}');
}
