import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir() { final es=Directory('../data/bsdata-es'); return es.existsSync()?es:Directory('../data/bsdata'); }
void main() async {
  final dataset = await Dataset.load(_dir());
  final dg = dataset.factionNamed('Chaos - Death Guard');
  final ds = dataset.detachmentsOf(dg);
  for (final tam in dataset.battleSizes) {
    final r = Roster(faction: dg, pointsLimit: tam.pointsLimit)..battleSize = tam;
    r.detachments.add(ds.firstWhere((d) => d.name == 'Tallyband Summoners'));
    final avisos = r.validate().map((v) => v.message).where((m) => !m.contains('puntos')).toList();
    print('${tam.name}: con Tallyband (2 DP) → ${avisos.isEmpty ? "legal" : avisos.join(" | ")}');

    r.detachments.add(ds.firstWhere((d) => d.name == 'Contagion Engines'));
    final a2 = r.validate().map((v) => v.message).where((m) => !m.contains('puntos')).toList();
    print('   + Contagion Engines (1 DP) = 3 DP → ${a2.isEmpty ? "legal" : a2.join(" | ")}');

    r.detachments.add(ds.firstWhere((d) => d.name == 'Flyblown Host'));
    final a3 = r.validate().map((v) => v.message).where((m) => !m.contains('puntos')).toList();
    print('   + Flyblown Host (1 DP) = 4 DP → ${a3.isEmpty ? "LEGAL (mal: se pasa)" : a3.join(" | ")}');
  }
}
