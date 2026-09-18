import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../tema.dart';
import 'facciones.dart';
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

  /// Las Legends se esconden de serie: son hojas retiradas que ya no se juegan, y en algunas
  /// facciones son casi la mitad del catálogo —116 de las 275 de los Ultramarines—.
  bool _legends = false;

  List<UnitEntry> get _visibles {
    var salida = _todas;
    if (!_legends) salida = salida.where((u) => !esLegends(u)).toList();
    if (_busqueda.isEmpty) return salida;
    final buscado = _normalizar(_busqueda);
    return salida.where((u) => _normalizar(u.name).contains(buscado)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final legends = _todas.where(esLegends).length;
    return ColorDeEjercito(
      color: colorDeFaccion(corto(widget.faccion.name)),
      child: Builder(builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(widget.faccion.name.split(' - ').last),
        actions: [
          if (legends > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BotonDeLegends(
                encendido: _legends,
                cuantas: legends,
                onChanged: (v) => setState(() => _legends = v),
              ),
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
      body: visibles.isEmpty
          ? const Center(
              child: Text('Ninguna unidad con ese nombre',
                  style: TextStyle(color: Tema.textoTenue)))
          : ListView.separated(
              itemCount: visibles.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _Unidad(unidad: visibles[i], faccion: widget.faccion),
            ),
      )),
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
