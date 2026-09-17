// ¿Llega cada unidad con sus miniaturas puestas? Sobre las 36 facciones.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final ds = await Dataset.load(_dir());
  var total=0, cortas=0;
  final ejemplos=<String>[];
  for (final f in ds.factions) {
    final dets = ds.detachmentsOf(f);
    if (dets.isEmpty) continue;
    final r = Roster(faction: f, pointsLimit: 3000)..detachments.add(dets.first);
    for (final u in f.units) {
      final s = r.selectionFor(u);
      total++;
      // ¿algún grupo se queda por debajo de su mínimo efectivo?
      for (final nodo in s.descendantsAndSelf.toList()) {
        for (final g in nodo.groups) {
          final uso = r.groupUsage(nodo, g);
          if (uso.minimo != null && uso.puestas < uso.minimo!) {
            cortas++;
            if (ejemplos.length < 12) {
              ejemplos.add('${f.name.split(' - ').last} · ${u.name} · '
                  '«${g.name}» ${uso.puestas}/${uso.minimo}');
            }
            break;
          }
        }
      }
    }
  }
  print('unidades: $total');
  print('que nacen por debajo de un mínimo: $cortas');
  for (final e in ejemplos) print('   $e');
}
