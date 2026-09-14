import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../tema.dart';
import 'unidad.dart';

/// Las unidades de una facción, buscables.
///
/// Un capítulo de Space Marines pasa de las trescientas, casi todas heredadas del codex común, así
/// que la búsqueda no es un adorno: sin ella no se encuentra nada.
class PantallaDeUnidades extends StatefulWidget {
  const PantallaDeUnidades({super.key, required this.faccion});

  final Faction faccion;

  @override
  State<PantallaDeUnidades> createState() => _PantallaDeUnidadesState();
}

class _PantallaDeUnidadesState extends State<PantallaDeUnidades> {
  late final List<UnitEntry> _todas = widget.faccion.units
    ..sort((a, b) => a.name.compareTo(b.name));
  String _busqueda = '';

  List<UnitEntry> get _visibles {
    if (_busqueda.isEmpty) return _todas;
    final buscado = _normalizar(_busqueda);
    return _todas.where((u) => _normalizar(u.name).contains(buscado)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.faccion.name.split(' - ').last),
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
      body: visibles.isEmpty
          ? const Center(
              child: Text('Ninguna unidad con ese nombre',
                  style: TextStyle(color: Tema.textoTenue)))
          : ListView.separated(
              itemCount: visibles.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _Unidad(unidad: visibles[i], faccion: widget.faccion),
            ),
    );
  }
}

class _Unidad extends StatelessWidget {
  const _Unidad({required this.unidad, required this.faccion});

  final UnitEntry unidad;
  final Faction faccion;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(unidad.name, style: const TextStyle(fontSize: 15)),
      subtitle: unidad.role == null
          ? null
          : Text(unidad.role!, style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
      trailing: Text(
        unidad.points == null ? '—' : '${unidad.points} pts',
        style: TextStyle(
          color: unidad.points == null ? Tema.textoTenue : Tema.acento,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PantallaDeUnidad(unidad: unidad, faccion: faccion),
      )),
    );
  }
}

/// Para buscar sin pelearse con tildes ni mayúsculas.
String _normalizar(String texto) {
  const con = 'áàäâéèëêíìïîóòöôúùüûñç';
  const sin = 'aaaaeeeeiiiioooouuuunc';
  final minusculas = texto.toLowerCase();
  final buffer = StringBuffer();
  for (final letra in minusculas.split('')) {
    final i = con.indexOf(letra);
    buffer.write(i == -1 ? letra : sin[i]);
  }
  return buffer.toString();
}
