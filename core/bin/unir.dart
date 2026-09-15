import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final ds = await Dataset.load(_dir());
  final dg = ds.factionNamed('Chaos - Death Guard');
  final r = Roster(faction: dg, pointsLimit: 2000)
    ..detachments.add(ds.detachmentsOf(dg).first);
  final marines = r.selectionFor(dg.units.firstWhere((u)=>u.name=='Plague Marines'));
  final lord = r.selectionFor(dg.units.firstWhere((u)=>u.name=='Lord of Virulence'));
  r..add(marines)..add(lord);
  print('¿a quién se puede unir el Lord of Virulence? ${r.hostsFor(lord).map((s)=>s.name).toList()}');
  final blight = r.selectionFor(dg.units.firstWhere((u)=>u.name=='Blightlord Terminators'));
  r.add(blight);
  print('con Blightlords en la lista:          ${r.hostsFor(lord).map((s)=>s.name).toList()}');
  r.attach(lord, blight);
  print('unido a ${lord.attachedTo?.name}; líderes sobre Blightlords: ${r.leadersOn(blight).map((s)=>s.name).toList()}');
  print('¿se puede unir otro líder ahí? ${r.hostsFor(lord).map((s)=>s.name).toList()}');
}
