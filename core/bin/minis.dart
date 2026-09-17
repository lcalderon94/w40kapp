import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final ds = await Dataset.load(_dir());
  for (final caso in [
    ['Chaos - Death Guard','Plague Marines'], ['Chaos - Death Guard','Poxwalkers'],
    ['Chaos - Death Guard','Blightlord Terminators'], ['Chaos - Death Guard','Deathshroud Terminators'],
    ['Imperium - Adeptus Astartes - Blood Angels','Intercessor Squad'],
    ['Imperium - Adeptus Astartes - Blood Angels','Sanguinary Guard'],
    ['Xenos - Necrons','Necron Warriors'], ['Xenos - Orks','Boyz'],
    ['Xenos - Tyranids','Termagants'], ['Imperium - Astra Militarum','Cadian Shock Troops'],
    ['Xenos - Aeldari','Guardian Defenders'], ['Xenos - Drukhari','Kabalite Warriors'],
  ]) {
    try {
      final f = ds.factionNamed(caso[0]);
      final u = f.units.where((x)=>x.name==caso[1]).firstOrNull;
      if (u==null) { print('${caso[1].padRight(26)} (no está en ${caso[0].split(' - ').last})'); continue; }
      final r = Roster(faction: f, pointsLimit: 3000)..detachments.add(ds.detachmentsOf(f).first);
      final s = r.selectionFor(u); r.add(s); r.applyModifiers();
      final n = s.descendantsAndSelf.where((x)=>x.type=='model').fold<int>(0,(t,x)=>t+x.count);
      final av = r.validate().length;
      print('${caso[1].padRight(26)} ${n.toString().padLeft(3)} miniaturas · ${s.points.toString().padLeft(4)} pts · ${av==0?"sin avisos":"$av avisos"}');
    } catch (e) { print('${caso[1]}: $e'); }
  }
}
