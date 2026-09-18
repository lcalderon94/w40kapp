import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import 'unidades.dart';

/// Las 36 facciones jugables, por familia y con buscador.
///
/// El dataset las nombra «Imperium - Adeptus Astartes - White Scars», que es exacto y se lee fatal
/// en una lista. Se parte por el guion: la familia queda de cabecera y la facción se queda con su
/// nombre corto, que es el que el jugador tiene en la cabeza.
///
/// La familia son **los dos primeros tramos cuando hay tres**, no solo el primero. Así los doce
/// capítulos de Space Marines quedan juntos bajo Adeptus Astartes en vez de repartidos entre las
/// dieciséis facciones del Imperium, que es lo que obligaba a recorrer la lista entera para dar
/// con los Ultramarines. Sale del propio nombre, no de una tabla escrita a mano.
class PantallaDeFacciones extends StatefulWidget {
  const PantallaDeFacciones({super.key});

  @override
  State<PantallaDeFacciones> createState() => _PantallaDeFaccionesState();
}

class _PantallaDeFaccionesState extends State<PantallaDeFacciones> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    var facciones = Datos.de(context).factions;
    if (_busqueda.trim().isNotEmpty) {
      final texto = _sinTildes(_busqueda);
      facciones =
          facciones.where((f) => _sinTildes(f.name).contains(texto)).toList();
    }

    final porFamilia = <String, List<Faction>>{};
    for (final faccion in facciones) {
      porFamilia.putIfAbsent(familia(faccion.name), () => []).add(faccion);
    }
    final familias = porFamilia.keys.toList()..sort(_ordenDeFamilia);

    return Scaffold(
      appBar: AppBar(title: const Text('Ejércitos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const ValueKey('buscar-faccion'),
              onChanged: (texto) => setState(() => _busqueda = texto),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Buscar ejército',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: familias.isEmpty
                ? const Center(
                    child: Text('Ningún ejército con ese nombre',
                        style: TextStyle(color: Tema.textoTenue)))
                : ListView.builder(
                    itemCount: familias.length,
                    itemBuilder: (context, i) {
                      final nombre = familias[i];
                      final suyas = porFamilia[nombre]!
                        ..sort((a, b) => corto(a.name).compareTo(corto(b.name)));
                      return _Familia(
                          nombre: nombre,
                          facciones: suyas,
                          abierta: _busqueda.trim().isNotEmpty);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Una familia, plegable. Empieza cerrada y se abre sola al buscar.
///
/// Cerradas caben las cinco de golpe en la pantalla y se elige en dos toques. Abiertas son
/// treinta y seis filas por las que hay que bajar, que es lo que había.
class _Familia extends StatelessWidget {
  const _Familia({required this.nombre, required this.facciones, required this.abierta});

  final String nombre;
  final List<Faction> facciones;
  final bool abierta;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('familia-$nombre-$abierta'),
        initiallyExpanded: abierta,
        title: Text(nombre.toUpperCase(),
            style: const TextStyle(
                color: Tema.acento,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4)),
        subtitle: Text('${facciones.length} ejércitos',
            style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
        iconColor: Tema.acento,
        collapsedIconColor: Tema.textoTenue,
        children: [for (final faccion in facciones) _Faccion(faccion)],
      ),
    );
  }
}

class _Faccion extends StatelessWidget {
  const _Faccion(this.faccion);

  final Faction faccion;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      title: Text(corto(faccion.name), style: const TextStyle(fontSize: 15.5)),
      trailing: const Icon(Icons.chevron_right, color: Tema.textoTenue, size: 20),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PantallaDeUnidades(faccion: faccion),
      )),
    );
  }
}

/// La familia de una facción: los dos primeros tramos del nombre si hay tres, y si no el primero.
///
/// «Imperium - Adeptus Astartes - Ultramarines» es de Adeptus Astartes; «Chaos - Death Guard» y
/// «Xenos - Orks», de Chaos y de Xenos.
String familia(String nombre) {
  final tramos = nombre.split(' - ');
  if (tramos.length >= 3) return '${tramos[0]} · ${tramos[1]}';
  return tramos.first;
}

/// El nombre corto: lo que va después del último guion.
String corto(String nombre) => nombre.split(' - ').last;

/// Imperium, Chaos y Xenos primero y en ese orden; las subfamilias, detrás de la suya.
int _ordenDeFamilia(String a, String b) {
  const bandos = ['Imperium', 'Chaos', 'Xenos'];
  final ba = bandos.indexOf(a.split(' · ').first);
  final bb = bandos.indexOf(b.split(' · ').first);
  if (ba != bb) return (ba < 0 ? bandos.length : ba).compareTo(bb < 0 ? bandos.length : bb);
  return a.compareTo(b);
}

String _sinTildes(String x) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  return x.toLowerCase().split('').map((c) => tildes[c] ?? c).join();
}
