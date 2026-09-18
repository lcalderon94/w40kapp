import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import 'unidades.dart';

/// Elegir ejército: por familia y de un vistazo.
///
/// Son 36 y en una lista plana hay que recorrerla entera. Aquí van en cuatro bloques —Chaos,
/// Imperium, Space Marines y Xenos— y cada uno como botones que caben en dos o tres filas, así que
/// se ve todo sin desplazar y se elige de un toque.
///
/// La familia sale del propio nombre del dataset: «Imperium - Adeptus Astartes - Ultramarines» es
/// de Space Marines y «Chaos - Death Guard» de Chaos. No hay ninguna tabla que mantener.
class PantallaDeFacciones extends StatefulWidget {
  const PantallaDeFacciones({super.key, this.alElegir, this.titulo = 'Ejércitos'});

  /// Qué hacer al elegir. Sin esto se abre el catálogo de la facción.
  final void Function(BuildContext, Faction)? alElegir;
  final String titulo;

  @override
  State<PantallaDeFacciones> createState() => _PantallaDeFaccionesState();
}

class _PantallaDeFaccionesState extends State<PantallaDeFacciones> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    var facciones = Datos.de(context).factions;
    if (_busqueda.trim().isNotEmpty) {
      final texto = sinTildes(_busqueda);
      facciones =
          facciones.where((f) => sinTildes(f.name).contains(texto)).toList();
    }

    final porFamilia = <String, List<Faction>>{};
    for (final faccion in facciones) {
      porFamilia.putIfAbsent(familia(faccion.name), () => []).add(faccion);
    }
    final familias = porFamilia.keys.toList()..sort(_ordenDeFamilia);

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('buscar-faccion'),
              onChanged: (texto) => setState(() => _busqueda = texto),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Buscar ejército',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: familias.isEmpty
                ? const Center(
                    child: Text('Ningún ejército con ese nombre',
                        style: TextStyle(color: Tema.textoTenue)))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final nombre in familias) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                                _Chip(
                                  faccion: faccion,
                                  alElegir: widget.alElegir ?? _abrirCatalogo,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _abrirCatalogo(BuildContext context, Faction faccion) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PantallaDeUnidades(faccion: faccion),
      ));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.faccion, required this.alElegir});

  final Faction faccion;
  final void Function(BuildContext, Faction) alElegir;

  @override
  Widget build(BuildContext context) {
    final nombre = corto(faccion.name);
    final color = colorDeFaccion(nombre);
    return SizedBox(
      width: 150,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('faccion-$nombre'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => alElegir(context, faccion),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(nombre,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _legible(color),
                    fontSize: 13.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Texto claro u oscuro según lo claro que sea el fondo, para que se lea siempre.
Color _legible(Color fondo) =>
    fondo.computeLuminance() > 0.5 ? const Color(0xFF14120F) : Colors.white;

/// El color con el que el juego identifica a cada ejército.
///
/// Son 36 y no cambian, así que van escritos: un color por hash daría botones distintos cada vez
/// que upstream renombrase algo, y aquí el color es justo lo que se reconoce sin leer.
Color colorDeFaccion(String nombre) =>
    _colores[nombre] ?? const Color(0xFF4A4642);

const _colores = <String, Color>{
  // Chaos
  'Chaos Daemons': Color(0xFF6B6577),
  'Chaos Knights': Color(0xFF4E7470),
  'Chaos Space Marines': Color(0xFF2E5C6E),
  'Death Guard': Color(0xFF7E8B3A),
  "Emperor's Children": Color(0xFFA85BA8),
  'Thousand Sons': Color(0xFF158C99),
  'World Eaters': Color(0xFF9B2226),
  'Titanicus Traitoris': Color(0xFF6E3A3A),
  // Imperium
  'Adepta Sororitas': Color(0xFFA51C21),
  'Adeptus Custodes': Color(0xFFBE9A63),
  'Adeptus Mechanicus': Color(0xFFB03A2E),
  'Adeptus Titanicus': Color(0xFF1F6FC4),
  'Astra Militarum': Color(0xFF5B7F5B),
  'Grey Knights': Color(0xFF6E8794),
  'Agents of the Imperium': Color(0xFF1F6E8C),
  'Imperial Knights': Color(0xFF7E938F),
  // Space Marines
  'Black Templars': Color(0xFF1E4E63),
  'Blood Angels': Color(0xFF9B1B22),
  'Dark Angels': Color(0xFF14522A),
  'Deathwatch': Color(0xFF7B8188),
  'Imperial Fists': Color(0xFFC79A15),
  'Iron Hands': Color(0xFF3A3A3A),
  'Raven Guard': Color(0xFF1B2733),
  'Salamanders': Color(0xFF18915C),
  'Space Marines': Color(0xFF7B8E93),
  'Space Wolves': Color(0xFF4E8794),
  'Ultramarines': Color(0xFF1668C7),
  'White Scars': Color(0xFF9A9A93),
  // Xenos
  'Aeldari': Color(0xFF1F8B93),
  'Drukhari': Color(0xFF1B6B83),
  'Genestealer Cults': Color(0xFF8B2C63),
  'Leagues of Votann': Color(0xFF7E8B85),
  'Necrons': Color(0xFF14874A),
  'Orks': Color(0xFF7E8B2A),
  "T'au Empire": Color(0xFF1F7E9B),
  'Tyranids': Color(0xFF8B3A9B),
};

/// La familia de una facción: Space Marines cuando el nombre lo dice, y si no el bando.
///
/// «Imperium - Adeptus Astartes - Ultramarines» es de Space Marines; «Chaos - Death Guard» y
/// «Xenos - Orks», de Chaos y de Xenos.
String familia(String nombre) {
  final tramos = nombre.split(' - ');
  if (tramos.length >= 3 && tramos[1] == 'Adeptus Astartes') return 'Space Marines';
  if (tramos.length >= 3) return tramos[1];
  return tramos.first;
}

/// El nombre corto: lo que va después del último guion.
String corto(String nombre) => nombre.split(' - ').last;

/// Chaos, Imperium, Space Marines y Xenos en ese orden, que es el que tiene el jugador en la
/// cabeza; lo que no encaje, detrás y por orden alfabético.
int _ordenDeFamilia(String a, String b) {
  const orden = ['Chaos', 'Imperium', 'Space Marines', 'Xenos'];
  final ia = orden.indexOf(a);
  final ib = orden.indexOf(b);
  if (ia != ib) {
    return (ia < 0 ? orden.length : ia).compareTo(ib < 0 ? orden.length : ib);
  }
  return a.compareTo(b);
}

String sinTildes(String x) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  return x.toLowerCase().split('').map((c) => tildes[c] ?? c).join();
}

/// Si una unidad es contenido Legends: hojas retiradas que ya no se juegan.
///
/// El dataset las marca en el nombre —«Wolf Guard Battle Leader [Legends]»— y son 2.393 de las
/// 6.149 del catálogo, así que enseñarlas mezcladas con las que sí se juegan es enterrar estas
/// últimas. En el constructor de listas quien las esconde es el propio dataset, con un
/// interruptor; en el catálogo no hay lista contra la que evaluarlo y se mira el nombre.
bool esLegends(UnitEntry unidad) => unidad.name.contains('[Legends]');

/// El interruptor de Legends, visible y a mano en vez de escondido en un menú.
class BotonDeLegends extends StatelessWidget {
  const BotonDeLegends({
    super.key,
    required this.encendido,
    required this.onChanged,
    this.cuantas,
  });

  final bool encendido;
  final ValueChanged<bool> onChanged;

  /// Cuántas hay, para que se vea qué se está escondiendo.
  final int? cuantas;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    return Material(
      color: encendido ? acento.withValues(alpha: 0.85) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: const ValueKey('boton-legends'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!encendido),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(encendido ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                  color: encendido
                      ? (acento.computeLuminance() > 0.45
                          ? const Color(0xFF14120F)
                          : Colors.white)
                      : Tema.textoTenue),
              const SizedBox(width: 6),
              Text(
                  cuantas == null ? 'Legends' : 'Legends${encendido ? "" : " ($cuantas)"}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: encendido
                          ? (acento.computeLuminance() > 0.45
                              ? const Color(0xFF14120F)
                              : Colors.white)
                          : Tema.textoTenue)),
            ],
          ),
        ),
      ),
    );
  }
}
