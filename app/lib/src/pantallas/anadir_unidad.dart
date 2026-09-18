import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../estado/lista_en_curso.dart';
import '../tema.dart';
import '../widgets/hoja_de_datos.dart';
import 'facciones.dart';

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
  bool _soloLasQueCaben = false;

  @override
  Widget build(BuildContext context) {
    final porRol = widget.lista.catalogoPorRol(
        busqueda: _busqueda, soloLasQueCaben: _soloLasQueCaben);
    final restantes = widget.lista.restantes;

    // El interruptor que el dataset usa para las Legends: es el mismo que decide si entran en la
    // lista, así que el botón enciende **eso** y no un filtro aparte que diría otra cosa.
    final legends = widget.lista.interruptores
        .where((r) => r.name == 'Show Legends')
        .firstOrNull;

    return ColorDeEjercito(
      color: colorDeFaccion(corto(widget.lista.faccion.name)),
      child: Builder(builder: (context) => Scaffold(
      appBar: AppBar(
        title: const Text('Añadir unidad'),
        actions: [
          if (legends != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: BotonDeLegends(
                  encendido: widget.lista.estaEncendido(legends.id),
                  onChanged: (v) {
                    widget.lista.cambiarInterruptor(legends.id, v);
                    setState(() {});
                  },
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.filter_alt_outlined,
                size: 20,
                color: _soloLasQueCaben ? ColorDeEjercito.de(context) : null),
            tooltip: 'Solo las que caben en $restantes pts',
            onPressed: () => setState(() => _soloLasQueCaben = !_soloLasQueCaben),
          ),
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
      body: porRol.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _soloLasQueCaben
                      ? 'Nada cabe en los $restantes pts que quedan.'
                      : 'No hay unidades que ofrecer.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tema.textoTenue),
                ),
              ),
            )
          // Por rol de batalla, en el orden de la hoja de ejército: buscar entre cientos de
          // unidades en una lista plana es lo que obliga a usar el buscador para todo.
          : ListView(
              children: [
                for (final grupo in porRol)
                  _GrupoDeRol(
                    rol: grupo.rol,
                    unidades: grupo.unidades,
                    restantes: restantes,
                    // Añadir no cierra la pantalla. Cerrarla obligaba a volver a entrar por cada
                    // unidad, y una lista se monta de diez en diez, no de una en una.
                    alAnadir: (u) {
                      widget.lista.anadirUnidad(u);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${u.name} añadida'),
                        duration: const Duration(milliseconds: 900),
                        behavior: SnackBarBehavior.floating,
                      ));
                    },
                    alMirar: (u) => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _FichaRapida(lista: widget.lista, unidad: u),
                    )),
                  ),
              ],
            ),
      )),
    );
  }
}

/// Un rol de batalla, desplegable, con sus unidades dentro.
class _GrupoDeRol extends StatefulWidget {
  const _GrupoDeRol({
    required this.rol,
    required this.unidades,
    required this.restantes,
    required this.alAnadir,
    required this.alMirar,
  });

  final String rol;
  final List<UnitEntry> unidades;
  final int restantes;
  final void Function(UnitEntry) alAnadir;
  final void Function(UnitEntry) alMirar;

  @override
  State<_GrupoDeRol> createState() => _GrupoDeRolState();
}

class _GrupoDeRolState extends State<_GrupoDeRol> {
  bool _abierto = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _abierto = !_abierto),
          child: Container(
            color: ColorDeEjercito.de(context).withValues(alpha: 0.85),
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.rol.toUpperCase(),
                      style: TextStyle(
                          color: ColorDeEjercito.de(context).computeLuminance() > 0.45
                              ? const Color(0xFF14120F)
                              : Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3)),
                ),
                Text('${widget.unidades.length}',
                    style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
                Icon(_abierto ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: Tema.textoTenue),
              ],
            ),
          ),
        ),
        if (_abierto)
          for (final unidad in widget.unidades)
            _FilaDeUnidad(
              unidad: unidad,
              cabe: (unidad.points ?? 0) <= widget.restantes,
              alAnadir: () => widget.alAnadir(unidad),
              alMirar: () => widget.alMirar(unidad),
            ),
      ],
    );
  }
}

/// Una unidad del catálogo: tocarla enseña su hoja, y el «+» la mete en la lista.
///
/// Eran la misma cosa y no lo son: se toca para saber qué es una unidad mucho más a menudo que
/// para meterla, y tocar por error metía una unidad en la lista sin haberla visto siquiera.
class _FilaDeUnidad extends StatelessWidget {
  const _FilaDeUnidad({
    required this.unidad,
    required this.cabe,
    required this.alAnadir,
    required this.alMirar,
  });

  final UnitEntry unidad;
  final bool cabe;
  final VoidCallback alAnadir;
  final VoidCallback alMirar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('unidad-${unidad.id}'),
      dense: true,
      title: Text(unidad.name,
          style: TextStyle(fontSize: 14.5, color: cabe ? Tema.texto : Tema.textoTenue)),
      subtitle: Text(unidad.role ?? '',
          style: const TextStyle(color: Tema.textoTenue, fontSize: 11.5)),
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
          const SizedBox(width: 2),
          IconButton(
            key: ValueKey('anadir-${unidad.id}'),
            onPressed: alAnadir,
            icon: const Icon(Icons.add_circle_outline, size: 24),
            color: Tema.acento,
            tooltip: 'Añadir a la lista',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      onTap: alMirar,
    );
  }
}

/// La hoja de datos de una unidad antes de meterla, con su botón de añadir.
class _FichaRapida extends StatelessWidget {
  const _FichaRapida({required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final UnitEntry unidad;

  @override
  Widget build(BuildContext context) {
    final dataset = Datos.de(context);
    return Scaffold(
      appBar: AppBar(title: Text(unidad.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          HojaDeDatos(
            perfiles: dataset.sheetOf(unidad),
            habilidades: dataset.abilitiesOf(unidad),
            palabrasClave: unidad.keywords,
            encabezado: BandaDeUnidad(
              nombre: unidad.name,
              rol: unidad.role,
              puntos: unidad.points,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('anadir-desde-ficha'),
        backgroundColor: ColorDeEjercito.de(context),
        foregroundColor: Tema.fondo,
        onPressed: () {
          lista.anadirUnidad(unidad);
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.add),
        label: const Text('Añadir a la lista'),
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
