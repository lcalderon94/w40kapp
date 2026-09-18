import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/almacen.dart';
import '../datos/repositorio.dart';
import '../estado/lista_en_curso.dart';
import '../tema.dart';
import 'facciones.dart';
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
          // Rejilla de tarjetas: de un vistazo se ve facción, detachment y puntos de cada lista,
          // que es lo que se mira al elegir cuál abrir.
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemCount: _listas.length,
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
    final detachment = lista.roster.detachments.isEmpty
        ? 'Sin detachment'
        : lista.roster.detachments.map((d) => d.name).join(' · ');

    return Material(
      color: Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PantallaDeLista(lista: lista)),
          );
          alVolver();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(lista.roster.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.15)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 19),
                    color: Tema.textoTenue,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _menu(context),
                  ),
                ],
              ),
              const Spacer(),
              Text(lista.faccion.name.split(' - ').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Tema.texto)),
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 1),
                child: Text(detachment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Tema.textoTenue)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(legal ? Icons.check_circle_outline : Icons.error_outline,
                      color: legal ? Tema.acento : Tema.aviso, size: 15),
                  const SizedBox(width: 5),
                  Text('${lista.puntos}/${lista.roster.pointsLimit} pts',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: legal ? Tema.texto : Tema.aviso)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Tema.superficie,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Renombrar'),
            onTap: () => Navigator.of(context).pop('renombrar'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Tema.aviso),
            title: const Text('Borrar', style: TextStyle(color: Tema.aviso)),
            onTap: () => Navigator.of(context).pop('borrar'),
          ),
        ]),
      ),
    );
    if (accion == 'borrar') alBorrar();
    if (accion == 'renombrar' && context.mounted) await _renombrar(context);
  }

  Future<void> _renombrar(BuildContext context) async {
    final control = TextEditingController(text: lista.roster.name);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tema.superficie,
        title: const Text('Nombre de la lista'),
        content: TextField(controller: control, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(control.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (nuevo != null && nuevo.isNotEmpty) {
      lista.renombrar(nuevo);
      alVolver();
    }
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
    final porFamilia = <String, List<Faction>>{};
    for (final faccion in widget.dataset.factions) {
      porFamilia.putIfAbsent(familia(faccion.name), () => []).add(faccion);
    }
    final familias = porFamilia.keys.toList()
      ..sort((a, b) => _ordenDeFamilia(a).compareTo(_ordenDeFamilia(b)));
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
          // Por familia y como botones: son 36 y en una lista plana hay que recorrerla entera.
          // Así caben las cuatro familias en la pantalla y se elige de un toque.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final nombre in familias) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(nombre.toUpperCase(),
                        style: const TextStyle(
                            color: Tema.textoTenue,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4)),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Tema.superficie,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final faccion in porFamilia[nombre]!
                          ..sort((a, b) => corto(a.name).compareTo(corto(b.name))))
                          _BotonDeFaccion(
                            faccion: faccion,
                            elegida: _faccion?.id == faccion.id,
                            onTap: () => setState(() => _faccion = faccion),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
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

/// Un ejército, con su color, dentro del bloque de su familia.
class _BotonDeFaccion extends StatelessWidget {
  const _BotonDeFaccion(
      {required this.faccion, required this.elegida, required this.onTap});

  final Faction faccion;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nombre = corto(faccion.name);
    final color = colorDeFaccion(nombre);
    return SizedBox(
      width: 150,
      child: Material(
        color: elegida ? color : color.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('faccion-$nombre'),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: elegida ? Border.all(color: Tema.texto, width: 2) : null,
            ),
            child: Text(nombre,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color.computeLuminance() > 0.5
                        ? const Color(0xFF14120F)
                        : Colors.white,
                    fontSize: 13.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

int _ordenDeFamilia(String nombre) {
  const orden = ['Chaos', 'Imperium', 'Space Marines', 'Xenos'];
  final i = orden.indexOf(nombre);
  return i < 0 ? orden.length : i;
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
