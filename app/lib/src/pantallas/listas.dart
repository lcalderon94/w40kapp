import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/almacen.dart';
import '../datos/repositorio.dart';
import '../estado/lista_en_curso.dart';
import '../tema.dart';
import 'lista.dart';

/// Las listas del jugador, guardadas en el teléfono.
///
/// Se guardan las **decisiones** —facción, tamaño, detachment, unidades y opciones—, no el árbol
/// resuelto: así una lista de hace tres meses se vuelve a montar con los puntos de hoy en vez de
/// quedarse congelada con los de entonces, que es como uno se presenta a jugar con una lista
/// ilegal creyéndola buena.
///
/// Se guarda en cuanto algo cambia, no con un botón: una app de listas que te pierde el trabajo
/// por no haber pulsado «guardar» no la usa nadie dos veces.
class PantallaDeListas extends StatefulWidget {
  const PantallaDeListas({super.key});

  @override
  State<PantallaDeListas> createState() => _PantallaDeListasState();
}

class _PantallaDeListasState extends State<PantallaDeListas> {
  final _listas = <ListaEnCurso>[];
  Almacen? _almacen;
  bool _cargando = true;
  int _ilegibles = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_almacen == null) _cargar();
  }

  Future<void> _cargar() async {
    final dataset = Datos.de(context);
    final almacen = await Almacen.abrir();
    final recuperadas = almacen.recuperar(dataset);
    if (!mounted) return;
    setState(() {
      _almacen = almacen;
      _cargando = false;
      _ilegibles = recuperadas.ilegibles;
      for (final r in recuperadas.listas) {
        final lista =
            ListaEnCurso.montada(dataset: dataset, roster: r.roster, perdidas: r.perdidas);
        _vigilar(lista);
        _listas.add(lista);
      }
    });
  }

  Future<void> _guardar() async {
    await _almacen?.escribir([for (final lista in _listas) lista.paraGuardar]);
  }

  /// Guarda en cuanto la lista cambia, esté donde esté el jugador. Una app de listas que te pierde
  /// el trabajo por no haber pulsado «guardar» no la usa nadie dos veces.
  void _vigilar(ListaEnCurso lista) => lista.addListener(_guardar);

  @override
  void dispose() {
    for (final lista in _listas) {
      lista.removeListener(_guardar);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Tema.acento)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mis listas')),
      body: _listas.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Todavía no hay ninguna lista.\nEmpieza eligiendo facción y tamaño de '
                      'partida.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Tema.textoTenue, height: 1.5),
                    ),
                    if (_ilegibles > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          '\$_ilegibles guardadas no se han podido leer.',
                          style: const TextStyle(color: Tema.aviso, fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _listas.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _Lista(
                lista: _listas[i],
                alBorrar: () {
                  _listas[i].removeListener(_guardar);
                  setState(() => _listas.removeAt(i));
                  _guardar();
                },
                alVolver: () {
                  setState(() {});
                  _guardar();
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Tema.acento,
        foregroundColor: Tema.fondo,
        icon: const Icon(Icons.add),
        label: const Text('Nueva lista'),
        onPressed: _nueva,
      ),
    );
  }

  Future<void> _nueva() async {
    final dataset = Datos.de(context);
    final creada = await Navigator.of(context).push<ListaEnCurso>(
      MaterialPageRoute(builder: (_) => PantallaDeNuevaLista(dataset: dataset)),
    );
    if (creada == null || !mounted) return;
    _vigilar(creada);
    setState(() => _listas.add(creada));
    await _guardar();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaDeLista(lista: creada)),
    );
    if (!mounted) return;
    setState(() {});
    await _guardar();
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.lista, required this.alBorrar, required this.alVolver});

  final ListaEnCurso lista;
  final VoidCallback alBorrar;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    final legal = lista.incumplimientos.isEmpty;
    return Dismissible(
      key: ObjectKey(lista),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Tema.aviso.withValues(alpha: 0.22),
        child: const Icon(Icons.delete_outline, color: Tema.aviso),
      ),
      onDismissed: (_) => alBorrar(),
      child: ListTile(
        title: Text(lista.roster.name, style: const TextStyle(fontSize: 15)),
        subtitle: Text(
          '${lista.faccion.name.split(' - ').last} · ${lista.roster.units.length} unidades',
          style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(legal ? Icons.check_circle_outline : Icons.error_outline,
                color: legal ? Tema.acento : Tema.aviso, size: 17),
            const SizedBox(width: 8),
            Text('${lista.puntos}/${lista.roster.pointsLimit}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PantallaDeLista(lista: lista)),
          );
          alVolver();
        },
      ),
    );
  }
}

/// Facción y tamaño de partida: lo único que hay que decidir para empezar.
///
/// El tamaño va aquí y no después porque **cambia las reglas**, no solo el límite de puntos: en
/// Incursion la mayoría de las unidades solo se pueden repetir dos veces y caben dos mejoras en
/// vez de cuatro. Elegirlo al final obligaría a rehacer la lista.
class PantallaDeNuevaLista extends StatefulWidget {
  const PantallaDeNuevaLista({super.key, required this.dataset});

  final Dataset dataset;

  @override
  State<PantallaDeNuevaLista> createState() => _PantallaDeNuevaListaState();
}

class _PantallaDeNuevaListaState extends State<PantallaDeNuevaLista> {
  Faction? _faccion;
  late BattleSize _tamano = widget.dataset.battleSizes
      .firstWhere((t) => t.pointsLimit == 2000, orElse: () => widget.dataset.battleSizes.first);

  @override
  Widget build(BuildContext context) {
    final facciones = widget.dataset.factions..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva lista')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                for (final tamano in widget.dataset.battleSizes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Tamano(
                        tamano: tamano,
                        elegido: _tamano.id == tamano.id,
                        onTap: () => setState(() => _tamano = tamano),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('FACCIÓN',
                  style: TextStyle(
                      color: Tema.acento,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4)),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: facciones.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final faccion = facciones[i];
                return ListTile(
                  title: Text(faccion.name.split(' - ').last,
                      style: const TextStyle(fontSize: 15)),
                  subtitle: Text(faccion.name.split(' - ').first,
                      style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
                  selected: _faccion?.id == faccion.id,
                  selectedColor: Tema.acento,
                  onTap: () => setState(() => _faccion = faccion),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Tema.acento,
                    foregroundColor: Tema.fondo,
                    disabledBackgroundColor: Tema.superficieAlta,
                  ),
                  onPressed: _faccion == null
                      ? null
                      : () => Navigator.of(context).pop(ListaEnCurso(
                            dataset: widget.dataset,
                            faccion: _faccion!,
                            tamano: _tamano,
                          )),
                  child: const Text('Crear lista'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tamano extends StatelessWidget {
  const _Tamano({required this.tamano, required this.elegido, required this.onTap});

  final BattleSize tamano;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: elegido ? Tema.acento.withValues(alpha: 0.16) : Tema.superficie,
          borderRadius: BorderRadius.circular(9),
          border: elegido ? Border.all(color: Tema.acento) : null,
        ),
        child: Column(
          children: [
            Text('${tamano.pointsLimit}',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: elegido ? Tema.acento : Tema.texto)),
            const SizedBox(height: 1),
            Text(_corto(tamano.name),
                style: const TextStyle(color: Tema.textoTenue, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

String _corto(String nombre) {
  final sinNumero = nombre.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  final parentesis = sinNumero.indexOf(' (');
  return parentesis == -1 ? sinNumero : sinNumero.substring(0, parentesis);
}
