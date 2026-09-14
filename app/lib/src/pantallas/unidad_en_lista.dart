import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';

/// Equipar una unidad de la lista: sus armas, su equipo y sus mejoras.
///
/// Las opciones van agrupadas como las agrupa el dataset, con el mínimo y el máximo del grupo a la
/// vista. Ese número no es el que trae escrito la restricción: el `core` lo recalcula con los
/// modifiers, que es lo que hace que «una pesada por cada cinco miniaturas» salga bien.
class PantallaDeUnidadEnLista extends StatelessWidget {
  const PantallaDeUnidadEnLista({super.key, required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lista,
      builder: (context, _) {
        final opciones = lista.opcionesDe(unidad);
        final porGrupo = <String?, List<Selection>>{};
        for (final opcion in opciones) {
          porGrupo.putIfAbsent(opcion.groupName, () => []).add(opcion);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(unidad.name),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text('${unidad.points} pts',
                      style: const TextStyle(
                          color: Tema.acento, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          body: opciones.isEmpty
              ? const Center(
                  child: Text('Esta unidad no tiene nada que elegir',
                      style: TextStyle(color: Tema.textoTenue)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    for (final grupo in porGrupo.entries)
                      _Grupo(
                        lista: lista,
                        unidad: unidad,
                        titulo: grupo.key,
                        opciones: grupo.value,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.lista,
    required this.unidad,
    required this.titulo,
    required this.opciones,
  });

  final ListaEnCurso lista;
  final Selection unidad;
  final String? titulo;
  final List<Selection> opciones;

  @override
  Widget build(BuildContext context) {
    final puestas = opciones.fold<int>(
        0, (total, opcion) => total + lista.cuantasHay(unidad, opcion.entryId));
    final limites = _limites(opciones.first.groupConstraints);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text((titulo ?? 'Opciones').toUpperCase(),
                    style: const TextStyle(
                        color: Tema.acento,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4)),
              ),
              if (limites != null)
                Text('$puestas de $limites',
                    style: const TextStyle(color: Tema.textoTenue, fontSize: 11.5)),
            ],
          ),
        ),
        for (final opcion in opciones)
          _Opcion(lista: lista, unidad: unidad, opcion: opcion),
      ],
    );
  }

  /// «1» si el grupo deja elegir una, «1-3» si deja un rango. `null` si no limita nada.
  String? _limites(List<Constraint> restricciones) {
    int? minimo, maximo;
    for (final restriccion in restricciones) {
      if (restriccion.field != 'selections') continue;
      if (restriccion.isMax) {
        maximo = restriccion.value.round();
      } else {
        minimo = restriccion.value.round();
      }
    }
    if (maximo != null && maximo < 0) maximo = null;
    if (minimo == null && maximo == null) return null;
    if (minimo == maximo) return '$minimo';
    return '${minimo ?? 0}-${maximo ?? "∞"}';
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.lista, required this.unidad, required this.opcion});

  final ListaEnCurso lista;
  final Selection unidad;
  final Selection opcion;

  @override
  Widget build(BuildContext context) {
    final cuantas = lista.cuantasHay(unidad, opcion.entryId);
    final puntos = opcion.basePointsEach;
    final mejora = opcion.baseCosts.containsKey(enhancementsCostTypeId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(opcion.name,
                    style: TextStyle(
                        fontSize: 14.5,
                        color: cuantas > 0 ? Tema.texto : Tema.textoTenue,
                        fontWeight: cuantas > 0 ? FontWeight.w600 : FontWeight.w400)),
                if (puntos > 0 || mejora)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      [
                        if (puntos > 0) '+$puntos pts',
                        if (mejora) 'mejora',
                      ].join(' · '),
                      style: const TextStyle(color: Tema.textoTenue, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          _Boton(
            icono: Icons.remove,
            activo: cuantas > 0,
            onPressed: () => lista.quitarOpcion(unidad, opcion.entryId),
          ),
          SizedBox(
            width: 28,
            child: Text('$cuantas',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cuantas > 0 ? Tema.acento : Tema.textoTenue)),
          ),
          _Boton(
            icono: Icons.add,
            activo: true,
            // `opcion` se construye de nuevo en cada build, así que añadirla no reutiliza un nodo
            // que ya cuelgue de la unidad.
            onPressed: () => lista.anadirOpcion(unidad, opcion),
          ),
        ],
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({required this.icono, required this.activo, required this.onPressed});

  final IconData icono;
  final bool activo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 19,
      color: activo ? Tema.texto : Tema.superficieAlta,
      onPressed: activo ? onPressed : null,
      icon: Icon(icono),
    );
  }
}
