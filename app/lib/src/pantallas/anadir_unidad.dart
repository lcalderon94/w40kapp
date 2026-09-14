import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';

/// Elegir qué unidad entra en la lista.
///
/// Se separan las que ya no caben en los puntos que quedan: no se esconden —el jugador puede estar
/// a punto de quitar otra cosa— pero se marcan, que es la diferencia entre ayudar y estorbar.
class PantallaDeAnadirUnidad extends StatefulWidget {
  const PantallaDeAnadirUnidad({super.key, required this.lista});

  final ListaEnCurso lista;

  @override
  State<PantallaDeAnadirUnidad> createState() => _PantallaDeAnadirUnidadState();
}

class _PantallaDeAnadirUnidadState extends State<PantallaDeAnadirUnidad> {
  late final List<UnitEntry> _todas = widget.lista.faccion.units
    ..sort((a, b) => a.name.compareTo(b.name));
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final buscado = _busqueda.toLowerCase();
    final visibles = buscado.isEmpty
        ? _todas
        : _todas.where((u) => u.name.toLowerCase().contains(buscado)).toList();
    final restantes = widget.lista.restantes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir unidad'),
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
