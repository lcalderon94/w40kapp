import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import 'unidades.dart';

/// Las 36 facciones jugables, agrupadas por bando.
///
/// El dataset las nombra «Imperium - Adeptus Astartes - White Scars», que es exacto y se lee fatal
/// en una lista. Se parte por el guion: el bando queda de cabecera y la facción se queda con su
/// nombre corto, que es el que el jugador tiene en la cabeza.
class PantallaDeFacciones extends StatelessWidget {
  const PantallaDeFacciones({super.key});

  @override
  Widget build(BuildContext context) {
    final facciones = Datos.de(context).factions;
    final porBando = <String, List<Faction>>{};
    for (final faccion in facciones) {
      porBando.putIfAbsent(_bando(faccion.name), () => []).add(faccion);
    }
    final bandos = porBando.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Ejércitos')),
      body: ListView.builder(
        itemCount: bandos.length,
        itemBuilder: (context, i) {
          final bando = bandos[i];
          final delBando = porBando[bando]!..sort((a, b) => _corto(a.name).compareTo(_corto(b.name)));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  bando.toUpperCase(),
                  style: const TextStyle(
                      color: Tema.acento,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6),
                ),
              ),
              for (final faccion in delBando) _Faccion(faccion),
            ],
          );
        },
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
      title: Text(_corto(faccion.name), style: const TextStyle(fontSize: 15.5)),
      trailing: const Icon(Icons.chevron_right, color: Tema.textoTenue, size: 20),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PantallaDeUnidades(faccion: faccion),
      )),
    );
  }
}

/// El bando: lo que va antes del primer guion. «Imperium», «Chaos», «Xenos».
String _bando(String nombre) => nombre.split(' - ').first;

/// El nombre corto: lo que va después del último guion.
String _corto(String nombre) => nombre.split(' - ').last;
