import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';
Directory _dir(){final es=Directory('../data/bsdata-es');return es.existsSync()?es:Directory('../data/bsdata');}
void main() async {
  final ds = await Dataset.load(_dir());
  print('roles que declara la fuerza, en orden:');
  for (final r in ds.standardForce.roles) print('   ${r.name}');
}
