import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir() { final es = Directory('../data/bsdata-es'); return es.existsSync() ? es : Directory('../data/bsdata'); }
void main() async {
  final dataset = await Dataset.load(_dir());
  for (final f in dataset.factions) {
    for (final d in dataset.detachmentsOf(f)) {
      print('${f.name}\t${d.name}');
    }
  }
}
