import 'package:flutter/material.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';

/// Elegir qué unidad entra en la lista.
///
/// Solo se ofrecen las que la lista puede llevar. El catálogo trae mucho más —Legends, aliados, y
/// las que piden un detachment concreto— y ofrecerlo todo es dar por buena una lista ilegal. Lo que
/// se puede encender se enciende a mano, con el botón de arriba.
///
/// Las que ya no caben en los puntos que quedan no se esconden —el jugador puede estar a punto de
/// quitar otra cosa— pero se marcan, que es la diferencia entre ayudar y estorbar.
class PantallaDeAnadirUnidad extends StatefulWidget {
  const PantallaDeAnadirUnidad({super.key, required this.lista});

  final ListaEnCurso lista;

  @override
  State<PantallaDeAnadirUnidad> createState() => _PantallaDeAnadirUnidadState();
}

class _PantallaDeAnadirUnidadState extends State<PantallaDeAnadirUnidad> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final todas = widget.lista.unidadesDisponibles
      ..sort((a, b) => a.name.compareTo(b.name));
    final buscado = _busqueda.toLowerCase();
    final visibles = buscado.isEmpty
        ? todas
        : todas.where((u) => u.name.toLowerCase().contains(buscado)).toList();
    final restantes = widget.lista.restantes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir unidad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: 'Qué contenido se ofrece',
            onPressed: () async {
              await showModalBottomSheet<void>(
                context: context,
                backgroundColor: Tema.superficie,
                builder: (_) => _Interruptores(lista: widget.lista),
              );
              setState(() {});
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (t) => setState(() => _busqueda = t),
              decoration: const InputDecoration(
                hintText: 'Buscar unidad',
                prefixIcon: Icon(Icons.search, color: Tema.textoTenue, size: 20),
              ),
            ),
          ),
        ),
      ),
      body: ListView.separated(
        itemCount: visibles.length,
        separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final unidad = visibles[i];
          final cabe = (unidad.points ?? 0) <= restantes;
          return ListTile(
            title: Text(unidad.name,
                style: TextStyle(fontSize: 15, color: cabe ? Tema.texto : Tema.textoTenue)),
            subtitle: unidad.role == null
                ? null
                : Text(unidad.role!,
                    style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!cabe)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: 'No cabe en los puntos que quedan',
                      child: Icon(Icons.warning_amber_rounded, color: Tema.aviso, size: 15),
                    ),
                  ),
                Text(unidad.points == null ? '—' : '${unidad.points} pts',
                    style: TextStyle(
                        color: cabe ? Tema.acento : Tema.textoTenue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            onTap: () {
              widget.lista.anadirUnidad(unidad);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}

/// Qué contenido del catálogo se ofrece: Legends, aliados, los demonios de cada dios.
///
/// El dataset los trae apagados y decide con ellos qué se puede meter en la lista. Son de la
/// facción, no globales: Chaos Daemons tiene uno por dios y Astra Militarum los Imperial Agents.
class _Interruptores extends StatefulWidget {
  const _Interruptores({required this.lista});

  final ListaEnCurso lista;

  @override
  State<_Interruptores> createState() => _InterruptoresState();
}

class _InterruptoresState extends State<_Interruptores> {
  @override
  Widget build(BuildContext context) {
    final opciones = widget.lista.interruptores;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('QUÉ CONTENIDO SE OFRECE',
                style: TextStyle(
                    color: Tema.acento,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'El catálogo trae más de lo que una lista puede llevar. Enciende solo lo que vayas '
              'a jugar.',
              style: TextStyle(color: Tema.textoTenue, fontSize: 12.5, height: 1.4),
            ),
          ),
          for (final opcion in opciones)
            SwitchListTile(
              value: widget.lista.estaEncendido(opcion.id),
              onChanged: (v) {
                widget.lista.cambiarInterruptor(opcion.id, v);
                setState(() {});
              },
              activeThumbColor: Tema.acento,
              title: Text(opcion.name.replaceFirst('Show ', ''),
                  style: const TextStyle(fontSize: 14.5)),
              dense: true,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
