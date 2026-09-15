import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

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
  bool _soloLasQueCaben = false;

  @override
  Widget build(BuildContext context) {
    final porRol = widget.lista.catalogoPorRol(
        busqueda: _busqueda, soloLasQueCaben: _soloLasQueCaben);
    final restantes = widget.lista.restantes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir unidad'),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_alt_outlined,
                size: 20, color: _soloLasQueCaben ? Tema.acento : null),
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
                    alElegir: (u) {
                      widget.lista.anadirUnidad(u);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
    );
  }
}

/// Un rol de batalla, desplegable, con sus unidades dentro.
class _GrupoDeRol extends StatefulWidget {
  const _GrupoDeRol({
    required this.rol,
    required this.unidades,
    required this.restantes,
    required this.alElegir,
  });

  final String rol;
  final List<UnitEntry> unidades;
  final int restantes;
  final void Function(UnitEntry) alElegir;

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
            color: Tema.superficieAlta,
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.rol.toUpperCase(),
                      style: const TextStyle(
                          color: Tema.acento,
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
              alElegir: () => widget.alElegir(unidad),
            ),
      ],
    );
  }
}

class _FilaDeUnidad extends StatelessWidget {
  const _FilaDeUnidad(
      {required this.unidad, required this.cabe, required this.alElegir});

  final UnitEntry unidad;
  final bool cabe;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(unidad.name,
          style: TextStyle(fontSize: 14.5, color: cabe ? Tema.texto : Tema.textoTenue)),
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
          const SizedBox(width: 4),
          const Icon(Icons.add, size: 18, color: Tema.textoTenue),
        ],
      ),
      onTap: alElegir,
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
