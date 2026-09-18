import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/almacen.dart';
import '../datos/repositorio.dart';
import '../tema.dart';
import 'facciones.dart';
import 'unidad.dart';

/// Buscar una unidad en las 36 facciones a la vez, y volver a lo último consultado.
///
/// Es la pregunta que más se hace en mitad de una partida —«¿qué hace esta unidad?»— y hasta ahora
/// obligaba a acordarse de a qué facción pertenece y entrar por ahí. El historial existe por lo
/// mismo: en una partida se consultan las mismas diez unidades una y otra vez.
class PantallaDeBuscar extends StatefulWidget {
  const PantallaDeBuscar({super.key});

  @override
  State<PantallaDeBuscar> createState() => _PantallaDeBuscarState();
}

class _PantallaDeBuscarState extends State<PantallaDeBuscar> {
  String _busqueda = '';
  Historial? _historial;
  List<({String faccion, String unidad})> _vistas = const [];

  @override
  void initState() {
    super.initState();
    Historial.abrir().then((h) {
      if (!mounted) return;
      setState(() {
        _historial = h;
        _vistas = h.entradas;
      });
    });
  }

  /// Todas las unidades del dataset, sin repetir y con la facción de la que salen.
  ///
  /// Sin repetir porque los capítulos de Space Marines comparten 161 unidades cada uno: sin esto,
  /// buscar «Intercessor» devuelve la misma doce veces.
  List<({Faction faccion, UnitEntry unidad})> _todas(Dataset dataset) {
    final salida = <({Faction faccion, UnitEntry unidad})>[];
    final vistas = <String>{};
    for (final faccion in dataset.factions) {
      for (final unidad in faccion.units) {
        if (!vistas.add(unidad.id)) continue;
        salida.add((faccion: faccion, unidad: unidad));
      }
    }
    return salida;
  }

  Future<void> _abrir(Faction faccion, UnitEntry unidad) async {
    await _historial?.apuntar(faccion: faccion.id, unidad: unidad.id);
    if (!mounted) return;
    setState(() => _vistas = _historial?.entradas ?? const []);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PantallaDeUnidad(unidad: unidad, faccion: faccion),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dataset = Datos.de(context);
    final texto = sinTildes(_busqueda);
    final resultados = texto.length < 2
        ? const <({Faction faccion, UnitEntry unidad})>[]
        : (_todas(dataset)
            .where((e) => sinTildes(e.unidad.name).contains(texto))
            .toList()
          ..sort((a, b) => a.unidad.name.compareTo(b.unidad.name)));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buscar'),
          bottom: const TabBar(
            labelColor: Tema.acento,
            unselectedLabelColor: Tema.textoTenue,
            indicatorColor: Tema.acento,
            tabs: [Tab(text: 'Unidades'), Tab(text: 'Historial')],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    key: const ValueKey('buscar-unidad'),
                    autofocus: false,
                    onChanged: (t) => setState(() => _busqueda = t),
                    decoration: const InputDecoration(
                      hintText: 'Nombre de la unidad',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: texto.length < 2
                      ? const Center(
                          child: Text('Escribe dos letras para buscar',
                              style: TextStyle(color: Tema.textoTenue)))
                      : resultados.isEmpty
                          ? const Center(
                              child: Text('Ninguna unidad con ese nombre',
                                  style: TextStyle(color: Tema.textoTenue)))
                          : ListView.builder(
                              itemCount: resultados.length,
                              itemBuilder: (context, i) => _Fila(
                                faccion: resultados[i].faccion,
                                unidad: resultados[i].unidad,
                                onTap: () =>
                                    _abrir(resultados[i].faccion, resultados[i].unidad),
                              ),
                            ),
                ),
              ],
            ),
            _Historial(
              vistas: _vistas,
              dataset: dataset,
              onTap: _abrir,
              onVaciar: () async {
                await _historial?.vaciar();
                if (!mounted) return;
                setState(() => _vistas = const []);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Historial extends StatelessWidget {
  const _Historial({
    required this.vistas,
    required this.dataset,
    required this.onTap,
    required this.onVaciar,
  });

  final List<({String faccion, String unidad})> vistas;
  final Dataset dataset;
  final Future<void> Function(Faction, UnitEntry) onTap;
  final VoidCallback onVaciar;

  @override
  Widget build(BuildContext context) {
    final filas = <({Faction faccion, UnitEntry unidad})>[];
    for (final v in vistas) {
      final faccion = dataset.factions.where((f) => f.id == v.faccion).firstOrNull;
      final unidad = faccion?.units.where((u) => u.id == v.unidad).firstOrNull;
      if (faccion != null && unidad != null) filas.add((faccion: faccion, unidad: unidad));
    }
    if (filas.isEmpty) {
      return const Center(
          child: Text('Aquí saldrá lo que vayas consultando',
              style: TextStyle(color: Tema.textoTenue)));
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onVaciar,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Vaciar'),
            style: TextButton.styleFrom(foregroundColor: Tema.textoTenue),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filas.length,
            itemBuilder: (context, i) => _Fila(
              faccion: filas[i].faccion,
              unidad: filas[i].unidad,
              onTap: () => onTap(filas[i].faccion, filas[i].unidad),
            ),
          ),
        ),
      ],
    );
  }
}

/// Una unidad encontrada, con la banda de color de su facción a la derecha.
class _Fila extends StatelessWidget {
  const _Fila({required this.faccion, required this.unidad, required this.onTap});

  final Faction faccion;
  final UnitEntry unidad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nombre = corto(faccion.name);
    final color = colorDeFaccion(nombre);
    final claro = color.computeLuminance() > 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: ValueKey('resultado-${unidad.id}'),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    size: 18, color: claro ? const Color(0xFF14120F) : Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(unidad.name,
                      style: TextStyle(
                          color: claro ? const Color(0xFF14120F) : Colors.white,
                          fontSize: 14.5)),
                ),
                Text(nombre.toUpperCase(),
                    style: TextStyle(
                        color: claro ? const Color(0xAA14120F) : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
