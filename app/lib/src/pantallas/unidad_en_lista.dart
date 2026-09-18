import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import '../widgets/hoja_de_datos.dart';

/// Equipar una unidad de la lista.
///
/// Una hoja de datos no es una lista plana de armas: es un árbol. Una escuadra tiene miniaturas,
/// cada miniatura tiene grupos de equipo, un grupo puede contener otros grupos y un arma puede
/// tener sus propias modificaciones. El Campeón de la Plaga lleva su equipo dos niveles por debajo
/// de la unidad. Pintando un solo nivel no se le puede dar un arma, que es justo lo que pasaba.
///
/// Los límites que se enseñan son los efectivos, no los declarados: el dataset los cambia con
/// modifiers («un arma pesada por cada cinco miniaturas») y el número escrito no es el que vale.
class PantallaDeUnidadEnLista extends StatelessWidget {
  const PantallaDeUnidadEnLista({super.key, required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lista,
      builder: (context, _) {
        final avisos = lista.incumplimientosDe(unidad);
        final entrada = lista.entradaDe(unidad);
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
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: BandaDeUnidad(
                  nombre: unidad.displayName,
                  subtitulo: unidad.customName != null ? unidad.name : null,
                  puntos: unidad.points,
                ),
              ),
              if (avisos.isNotEmpty) _Avisos(avisos: avisos),
              const _Titulo('Composición y equipo'),
              _Nodo(lista: lista, nodo: unidad, profundidad: 0),
              // Ver y editar en la misma pantalla: al equipar hace falta saber qué hace el arma
              // que se elige, y tener que salir a la ficha para averiguarlo es perder el sitio.
              //
              // Y con lo que lleva puesto, no con todo lo que podría llevar: si a los Plague
              // Marines les he quitado los bólters, el bólter no pinta nada en su hoja, y el
              // Caladius Grav-tank tiene que enseñar el cañón que le he puesto y no los tres que
              // no. Eso solo vale aquí; en el catálogo se enseña todo, que es donde se compara.
              if (entrada != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: HojaDeDatos(
                    perfiles: lista.hojaDe(unidad),
                    palabrasClave: entrada.keywords,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Tema.superficieAlta,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      margin: const EdgeInsets.only(top: 8),
      child: Text(texto.toUpperCase(),
          style: const TextStyle(
              color: Tema.acento,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3)),
    );
  }
}

class _Avisos extends StatelessWidget {
  const _Avisos({required this.avisos});

  final List<Violation> avisos;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Tema.aviso.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Tema.aviso.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final aviso in avisos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(aviso.message,
                  style: const TextStyle(color: Tema.aviso, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

/// Un nivel del árbol: lo que este nodo ofrece, y debajo lo que ya cuelga de él.
class _Nodo extends StatelessWidget {
  const _Nodo({required this.lista, required this.nodo, required this.profundidad});

  final ListaEnCurso lista;
  final Selection nodo;
  final int profundidad;

  @override
  Widget build(BuildContext context) {
    final ofrecidas = lista.opcionesDe(nodo);

    // Los grupos de primer nivel de este nodo. Los anidados los pinta su grupo padre.
    final raiz = nodo.groups.where((g) => g.parentId == null).toList();
    // Lo que no sale de ningún grupo: equipo suelto de la miniatura.
    final sueltas = ofrecidas.where((o) => o.groupId == null).toList();

    // Puesto y ya no ofrecido: equipo que el dataset da de serie y no se puede cambiar. Se enseña
    // igual, porque forma parte de la miniatura y el jugador tiene que verlo.
    final ofrecidosIds =
        ofrecidas.map((o) => '${o.entryId}|${o.groupId}').toSet();
    final fijos = nodo.children
        .where((h) => !ofrecidosIds.contains('${h.entryId}|${h.groupId}'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final grupo in raiz)
          _Grupo(
              lista: lista,
              dueno: nodo,
              grupo: grupo,
              ofrecidas: ofrecidas,
              sangria: profundidad),
        if (sueltas.isNotEmpty || fijos.isNotEmpty)
          _Seccion(
            titulo: profundidad == 0 ? 'Equipo' : null,
            sangria: profundidad,
            hijos: [
              for (final o in sueltas)
                _Opcion(
                    lista: lista,
                    dueno: nodo,
                    opcion: o,
                    radio: false,
                    sangria: profundidad),
              for (final f in fijos)
                _Opcion(
                    lista: lista,
                    dueno: nodo,
                    opcion: f,
                    radio: false,
                    sangria: profundidad,
                    fijo: true),
            ],
          ),
      ],
    );
  }
}

/// Un grupo de opciones, con su límite efectivo y los subgrupos que anidan dentro.
class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.lista,
    required this.dueno,
    required this.grupo,
    required this.ofrecidas,
    required this.sangria,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;
  final List<Selection> ofrecidas;
  final int sangria;

  @override
  Widget build(BuildContext context) {
    final uso = lista.usoDeGrupo(dueno, grupo);
    final mias = ofrecidas.where((o) => o.groupId == grupo.id).toList();
    final anidados = dueno.groups.where((g) => g.parentId == grupo.id).toList();
    // Un grupo que solo deja elegir una cosa es un botón de radio, no un contador.
    final radio = uso.maximo == 1;
    // Y si además exige una, no se puede dejar vacío: pulsar elige, nunca desmarca.
    final obligatorio = (uso.minimo ?? 0) > 0;

    return _Seccion(
      titulo: grupo.name ?? 'Opciones',
      contador: _contador(uso),
      incumple: _incumple(uso),
      sangria: sangria,
      hijos: [
        for (final o in mias)
          _Opcion(
              lista: lista,
              dueno: dueno,
              opcion: o,
              radio: radio,
              obligatorio: obligatorio,
              sangria: sangria),
        for (final sub in anidados)
          _Grupo(
              lista: lista,
              dueno: dueno,
              grupo: sub,
              ofrecidas: ofrecidas,
              sangria: sangria + 1),
      ],
    );
  }

  bool _incumple(({int puestas, int? minimo, int? maximo}) uso) =>
      (uso.minimo != null && uso.puestas < uso.minimo!) ||
      (uso.maximo != null && uso.puestas > uso.maximo!);

  /// «1 de 1», «2 de 0-2», o solo el número puesto si el dataset no pone tope.
  String? _contador(({int puestas, int? minimo, int? maximo}) uso) {
    if (uso.minimo == null && uso.maximo == null) return null;
    if (uso.minimo == uso.maximo) return '${uso.puestas} de ${uso.maximo}';
    final tope = uso.maximo?.toString() ?? '∞';
    return '${uso.puestas} de ${uso.minimo ?? 0}-$tope';
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    this.titulo,
    this.contador,
    this.incumple = false,
    required this.sangria,
    required this.hijos,
  });

  final String? titulo;
  final String? contador;
  final bool incumple;
  final int sangria;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titulo != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16.0 + sangria * 12, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(titulo!.toUpperCase(),
                      style: TextStyle(
                          color: incumple ? Tema.aviso : Tema.acento,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3)),
                ),
                if (contador != null)
                  Text(contador!,
                      style: TextStyle(
                          color: incumple ? Tema.aviso : Tema.textoTenue, fontSize: 11.5)),
              ],
            ),
          ),
        ...hijos,
      ],
    );
  }
}

/// Una opción: contador si caben varias, marca si solo cabe una.
///
/// Si lo puesto tiene a su vez equipo que elegir, la misma fila se despliega y enseña ese nivel
/// dentro. Así el Campeón de la Plaga sale una sola vez —no como opción y como fila aparte— y su
/// equipo queda a un toque, que es lo que hay que poder hacer.
class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.lista,
    required this.dueno,
    required this.opcion,
    required this.radio,
    required this.sangria,
    this.obligatorio = false,
    this.fijo = false,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;
  final bool radio;
  final int sangria;

  /// Si el grupo del que sale exige elegir algo, y por tanto no se puede dejar vacío.
  final bool obligatorio;

  /// Equipo que el dataset da de serie: se enseña, pero no se toca.
  final bool fijo;

  @override
  Widget build(BuildContext context) {
    final puesta = dueno.puestaDe(opcion);
    final dentro = puesta != null &&
        (puesta.groups.isNotEmpty || lista.opcionesDe(puesta).isNotEmpty);

    final fila = _fila(context, puesta?.count ?? 0);
    if (!dentro) return fila;

    final avisos = lista.incumplimientosDe(puesta).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: avisos > 0,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: fila,
        subtitle: avisos == 0
            ? null
            : Padding(
                padding: EdgeInsets.only(left: 16.0 + sangria * 12, bottom: 6),
                child: Text(
                    avisos == 1 ? 'falta algo por elegir' : '$avisos cosas por elegir',
                    style: const TextStyle(color: Tema.aviso, fontSize: 11.5)),
              ),
        children: [_Nodo(lista: lista, nodo: puesta, profundidad: sangria + 1)],
      ),
    );
  }

  Widget _fila(BuildContext context, int cuantas) {
    // Clave estable, y con el grupo dentro: la misma arma sale en dos grupos del Defiler, así que
    // con la entrada sola las dos filas compartían clave y no se podían distinguir al tocarlas.
    final clave = ValueKey('opcion-${opcion.entryId}-${opcion.groupId}');
    // Equipo de serie que el dataset no deja cambiar: mínimo y máximo iguales. Las Shearing claws
    // del Defiler son `min 1, max 1`, o sea que las lleva y punto. Un contador ahí ofrece bajarlas
    // a cero, que deja la unidad ilegal por algo que no era una elección.
    final bloqueada = fijo || (!radio && lista.esFija(dueno, opcion));
    final puntos = opcion.basePointsEach;
    final mejora = opcion.baseCosts.containsKey(enhancementsCostTypeId);

    final etiqueta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(opcion.name,
            style: TextStyle(
                fontSize: 14,
                color: cuantas > 0 || bloqueada ? Tema.texto : Tema.textoTenue,
                fontWeight: cuantas > 0 ? FontWeight.w600 : FontWeight.w400)),
        if (puntos > 0 || mejora)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              [if (puntos > 0) '+$puntos pts', if (mejora) 'mejora'].join(' · '),
              style: const TextStyle(color: Tema.textoTenue, fontSize: 11),
            ),
          ),
      ],
    );

    final margen = EdgeInsets.only(left: 16.0 + sangria * 12, right: 16);

    if (bloqueada) {
      return Padding(
        key: clave,
        padding: margen.add(const EdgeInsets.symmetric(vertical: 6)),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 15, color: Tema.textoTenue),
          const SizedBox(width: 11),
          Expanded(child: etiqueta),
          if (cuantas > 1)
            Text('×$cuantas',
                style: const TextStyle(color: Tema.textoTenue, fontSize: 12.5)),
        ]),
      );
    }

    if (radio) {
      return InkWell(
        key: clave,
        // Si el grupo exige elegir algo, pulsar **elige**: sustituye a lo que hubiera y no deja
        // desmarcar. Dejarlo desmarcar era lo que ponía «el baleflamer es obligatorio» en el
        // Defiler; un arma no es obligatoria, lo es elegir una de las cuatro. Si el grupo admite
        // el vacío, sí alterna: una mejora se pone y se quita.
        onTap: () => obligatorio
            ? lista.elegirOpcion(dueno, opcion)
            : lista.alternarOpcion(dueno, opcion),
        child: Padding(
          padding: margen.add(const EdgeInsets.symmetric(vertical: 8)),
          child: Row(children: [
            Icon(cuantas > 0 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 19, color: cuantas > 0 ? Tema.acento : Tema.textoTenue),
            const SizedBox(width: 12),
            Expanded(child: etiqueta),
          ]),
        ),
      );
    }

    return Padding(
      key: clave,
      padding: margen.add(const EdgeInsets.symmetric(vertical: 3)),
      child: Row(children: [
        Expanded(child: etiqueta),
        _Boton(
          icono: Icons.remove,
          // Hasta el suelo que pone el dataset, no hasta cero: hay opciones con un mínimo propio
          // —«una escuadra lleva cuatro con bólter»— y bajarlas de ahí deja la unidad ilegal.
          activo: cuantas > 0 && lista.sePuedeQuitar(dueno, opcion),
          onPressed: () => lista.quitarOpcion(dueno, opcion),
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
          // El techo lo dice el dataset, en la opción y en su grupo. Sin comprobarlo se puede
          // pulsar para siempre: veinte Rotwinds en Mortarion, que lleva uno.
          activo: lista.cabeOtra(dueno, opcion),
          // `opcion` se construye de nuevo en cada build, así que añadirla no reutiliza un nodo
          // que ya cuelgue de la unidad.
          onPressed: () => lista.anadirOpcion(dueno, opcion),
        ),
      ]),
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
      onPressed: activo ? onPressed : null,
      icon: Icon(icono, size: 19),
      color: Tema.texto,
      disabledColor: Tema.textoTenue.withValues(alpha: 0.35),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}
