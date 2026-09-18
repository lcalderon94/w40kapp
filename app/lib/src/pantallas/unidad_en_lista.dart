import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import '../widgets/hoja_de_datos.dart';

/// Equipar una unidad de la lista.
///
/// El orden es el de la hoja impresa y el de WarOrgan: primero **qué hay que decidir** —cuántas
/// miniaturas y con qué van— y debajo la hoja de datos de lo que ha quedado. Así se elige mirando
/// el arma que se elige, sin salir de la pantalla.
///
/// Una hoja de datos no es una lista plana de armas: es un árbol. Una escuadra tiene miniaturas,
/// cada miniatura tiene grupos de equipo, un grupo puede contener otros grupos y un arma puede
/// tener sus propias modificaciones. El Campeón de la Plaga lleva su equipo dos niveles por debajo
/// de la unidad.
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _Nodo(lista: lista, nodo: unidad, profundidad: 0),
              ),
              _Union(lista: lista, unidad: unidad),
              _NombrePropio(lista: lista, unidad: unidad),
              // Y debajo, lo que ha quedado: la hoja de datos de lo que lleva puesto, no de todo
              // lo que podría llevar. El Caladius enseña el cañón que le he puesto y no los tres
              // que no; los Plague Marines sin bólters no enseñan el bólter.
              if (entrada != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: HojaDeDatos(
                    perfiles: lista.hojaDe(unidad),
                    habilidades: lista.habilidadesDe(unidad),
                    cuantas: lista.armasDe(unidad),
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
      margin: const EdgeInsets.only(top: 14, bottom: 8),
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
    final raiz = nodo.groups.where((g) => g.parentId == null).toList();
    final sueltas = ofrecidas.where((o) => o.groupId == null).toList();

    // Puesto y ya no ofrecido: equipo de serie que no se puede cambiar. Se enseña igual, porque
    // forma parte de la miniatura y el jugador tiene que verlo.
    final ofrecidosIds = ofrecidas.map((o) => '${o.entryId}|${o.groupId}').toSet();
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
              profundidad: profundidad),
        if (sueltas.isNotEmpty || fijos.isNotEmpty)
          _Caja(
            titulo: profundidad == 0 ? 'Equipo' : null,
            hijos: [
              for (final o in sueltas)
                _Fila(
                    lista: lista,
                    dueno: nodo,
                    opcion: o,
                    // Sin grupo cada pieza va por su cuenta: no hay nada que ponerle en su lugar.
                    hayAlternativas: false,
                    profundidad: profundidad),
              for (final f in fijos)
                _Fila(
                    lista: lista,
                    dueno: nodo,
                    opcion: f,
                    hayAlternativas: false,
                    profundidad: profundidad,
                    fijo: true),
            ],
          ),
      ],
    );
  }
}

/// Un grupo de opciones, con su límite efectivo y los subgrupos que anidan dentro.
///
/// Se pinta de dos maneras según lo que el dataset permita, que es lo que las hace distintas:
/// cuando solo cabe una, botones —«elige una de estas»—; cuando caben varias, contadores.
class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.lista,
    required this.dueno,
    required this.grupo,
    required this.ofrecidas,
    required this.profundidad,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;
  final List<Selection> ofrecidas;
  final int profundidad;

  @override
  Widget build(BuildContext context) {
    final uso = lista.usoDeGrupo(dueno, grupo);
    final mias = ofrecidas.where((o) => o.groupId == grupo.id).toList();
    final anidados = dueno.groups.where((g) => g.parentId == grupo.id).toList();
    final unaSola = uso.maximo == 1;
    final obligatorio = (uso.minimo ?? 0) > 0;
    final incumple = (uso.minimo != null && uso.puestas < uso.minimo!) ||
        (uso.maximo != null && uso.puestas > uso.maximo!);

    return _Caja(
      titulo: grupo.name ?? 'Opciones',
      contador: _contador(uso),
      pista: _pista(uso),
      incumple: incumple,
      hijos: [
        if (unaSola && mias.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in mias)
                  _BotonDeOpcion(
                    lista: lista,
                    dueno: dueno,
                    opcion: o,
                    obligatorio: obligatorio,
                  ),
              ],
            ),
          )
        else
          for (final o in mias)
            _Fila(
                lista: lista,
                dueno: dueno,
                opcion: o,
                hayAlternativas: mias.length > 1,
                profundidad: profundidad),
        for (final sub in anidados)
          _Grupo(
              lista: lista,
              dueno: dueno,
              grupo: sub,
              ofrecidas: ofrecidas,
              profundidad: profundidad + 1),
      ],
    );
  }

  /// «1 de 1», «2 de 0-2», o solo el número puesto si el dataset no pone tope.
  String? _contador(({int puestas, int? minimo, int? maximo}) uso) {
    if (uso.minimo == null && uso.maximo == null) return null;
    if (uso.minimo == uso.maximo) return '${uso.puestas} de ${uso.maximo}';
    final tope = uso.maximo?.toString() ?? '∞';
    return '${uso.puestas} de ${uso.minimo ?? 0}-$tope';
  }

  /// Lo que el dataset pide, dicho en castellano, como en la hoja: «elige una de estas».
  String? _pista(({int puestas, int? minimo, int? maximo}) uso) {
    if (uso.maximo == 1) return uso.minimo == 1 ? 'Elige una de estas' : 'Puedes elegir una';
    if (uso.minimo != null && uso.minimo == uso.maximo) return 'Exactamente ${uso.minimo}';
    if (uso.maximo != null) return 'Hasta ${uso.maximo}';
    if (uso.minimo != null) return 'Mínimo ${uso.minimo}';
    return null;
  }
}

/// El recuadro de un grupo: su nombre, lo que pide y lo que hay dentro.
class _Caja extends StatelessWidget {
  const _Caja({
    this.titulo,
    this.contador,
    this.pista,
    this.incumple = false,
    required this.hijos,
  });

  final String? titulo;
  final String? contador;
  final String? pista;
  final bool incumple;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: incumple ? Tema.aviso.withValues(alpha: 0.6) : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titulo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: Tema.superficieAlta,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo!.toUpperCase(),
                            style: TextStyle(
                                color: incumple ? Tema.aviso : Tema.acento,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        if (pista != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(pista!,
                                style: const TextStyle(
                                    color: Tema.textoTenue, fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ),
                  if (contador != null)
                    Text(contador!,
                        style: TextStyle(
                            color: incumple ? Tema.aviso : Tema.textoTenue,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ...hijos,
        ],
      ),
    );
  }
}

/// Un botón de un grupo del que solo cabe una cosa.
///
/// Pulsar **elige**: pone esta y quita la que hubiera. Si el grupo admite quedarse vacío —una
/// mejora—, volver a pulsar la quita; si el dataset exige una, no se puede dejar el hueco.
class _BotonDeOpcion extends StatelessWidget {
  const _BotonDeOpcion({
    required this.lista,
    required this.dueno,
    required this.opcion,
    required this.obligatorio,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;
  final bool obligatorio;

  @override
  Widget build(BuildContext context) {
    final puesta = dueno.puestaDe(opcion) != null;
    final puntos = opcion.basePointsEach;
    final mejora = opcion.baseCosts.containsKey(enhancementsCostTypeId);

    return Material(
      color: puesta ? Tema.acento.withValues(alpha: 0.22) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('opcion-${opcion.entryId}-${opcion.groupId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => obligatorio
            ? lista.elegirOpcion(dueno, opcion)
            : lista.alternarOpcion(dueno, opcion),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: puesta ? Tema.acento : Tema.superficieAlta, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(opcion.name,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: puesta ? Tema.texto : Tema.textoTenue,
                      fontWeight: puesta ? FontWeight.w700 : FontWeight.w400)),
              if (puntos > 0 || mejora)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      [if (puntos > 0) '+$puntos pts', if (mejora) 'mejora'].join(' · '),
                      style: const TextStyle(color: Tema.acento, fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila con contador: cuántas de esto lleva la unidad.
///
/// Si lo puesto tiene a su vez equipo que elegir, la fila se despliega y enseña ese nivel dentro.
/// Así el Campeón de la Plaga sale una vez —no como opción y como fila aparte— y su equipo queda a
/// un toque, que es lo que hay que poder hacer.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.lista,
    required this.dueno,
    required this.opcion,
    required this.hayAlternativas,
    required this.profundidad,
    this.fijo = false,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;

  /// Si su grupo ofrece otra cosa en su lugar. Con alternativas nada es equipo fijo: es lo que
  /// está puesto ahora, y el grupo existe justo para cambiarlo.
  final bool hayAlternativas;
  final int profundidad;

  /// Equipo que el dataset da de serie y ya no ofrece: se enseña, pero no se toca.
  final bool fijo;

  @override
  Widget build(BuildContext context) {
    final puesta = dueno.puestaDe(opcion);
    final dentro = puesta != null &&
        (puesta.groups.isNotEmpty || lista.opcionesDe(puesta).isNotEmpty);

    final fila = _contenido(context, puesta?.count ?? 0);
    if (!dentro) return fila;

    final avisos = lista.incumplimientosDe(puesta).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: avisos > 0,
        tilePadding: const EdgeInsets.only(right: 8),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 6, 8),
        title: fila,
        subtitle: avisos == 0
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Text(
                    avisos == 1 ? 'falta algo por elegir' : '$avisos cosas por elegir',
                    style: const TextStyle(color: Tema.aviso, fontSize: 11.5)),
              ),
        children: [_Nodo(lista: lista, nodo: puesta, profundidad: profundidad + 1)],
      ),
    );
  }

  Widget _contenido(BuildContext context, int cuantas) {
    final clave = ValueKey('opcion-${opcion.entryId}-${opcion.groupId}');
    // Equipo de serie que el dataset no deja cambiar: mínimo y máximo iguales **y** sin nada que
    // ponerle en su lugar. Con alternativas no es fijo, es lo que hay puesto.
    final bloqueada = fijo || lista.esFija(dueno, opcion, hayAlternativas: hayAlternativas);
    final puntos = opcion.basePointsEach;
    final mejora = opcion.baseCosts.containsKey(enhancementsCostTypeId);

    final etiqueta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(opcion.name,
            style: TextStyle(
                fontSize: 14.5,
                color: cuantas > 0 || bloqueada ? Tema.texto : Tema.textoTenue,
                fontWeight: cuantas > 0 ? FontWeight.w600 : FontWeight.w400)),
        if (puntos > 0 || mejora)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              [if (puntos > 0) '+$puntos pts', if (mejora) 'mejora'].join(' · '),
              style: const TextStyle(color: Tema.acento, fontSize: 11),
            ),
          ),
      ],
    );

    if (bloqueada) {
      return Padding(
        key: clave,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 15, color: Tema.textoTenue),
          const SizedBox(width: 11),
          Expanded(child: etiqueta),
          if (cuantas > 1)
            Text('×$cuantas',
                style: const TextStyle(color: Tema.textoTenue, fontSize: 13)),
        ]),
      );
    }

    // El contador, como el de WarOrgan: menos, el número grande y más.
    return Padding(
      key: clave,
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(children: [
        Expanded(child: etiqueta),
        _Boton(
          icono: Icons.remove,
          // Hasta el suelo que pone el dataset, no hasta cero.
          activo: cuantas > 0 &&
              lista.sePuedeQuitar(dueno, opcion, hayAlternativas: hayAlternativas),
          onPressed: () => lista.quitarOpcion(dueno, opcion),
        ),
        SizedBox(
          width: 32,
          child: Text('$cuantas',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cuantas > 0 ? Tema.acento : Tema.textoTenue)),
        ),
        _Boton(
          icono: Icons.add,
          activo: lista.cabeOtra(dueno, opcion),
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
      icon: Icon(icono, size: 20),
      color: Tema.texto,
      disabledColor: Tema.textoTenue.withValues(alpha: 0.3),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      padding: EdgeInsets.zero,
    );
  }
}

/// A qué unidad se une este líder, o qué líderes lleva esta unidad.
class _Union extends StatelessWidget {
  const _Union({required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    final anfitriones = lista.anfitrionesDe(unidad);
    final lideres = lista.lideresDe(unidad);
    if (anfitriones.isEmpty && lideres.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titulo('Unidades adjuntas'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _Caja(
            titulo: anfitriones.isNotEmpty ? 'Se une a' : 'Lleva adjunto',
            pista: anfitriones.isNotEmpty ? 'Elige a quién acompaña' : null,
            hijos: [
              for (final lider in lideres)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link, size: 18, color: Tema.acento),
                  title: Text(lider.displayName, style: const TextStyle(fontSize: 14)),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off, size: 18),
                    color: Tema.textoTenue,
                    onPressed: () => lista.unir(lider, null),
                  ),
                ),
              if (anfitriones.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final anfitrion in anfitriones)
                        _BotonDeAnfitrion(
                          lista: lista,
                          lider: unidad,
                          anfitrion: anfitrion,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BotonDeAnfitrion extends StatelessWidget {
  const _BotonDeAnfitrion(
      {required this.lista, required this.lider, required this.anfitrion});

  final ListaEnCurso lista;
  final Selection lider;
  final Selection anfitrion;

  @override
  Widget build(BuildContext context) {
    final unido = lider.attachedTo == anfitrion;
    // Ya lleva otro de la misma clase. No se impide —hay hojas que lo permiten y el dataset no lo
    // dice— pero se avisa, que es lo que el jugador necesita para decidir.
    final ocupado = lista.anfitrionOcupado(lider, anfitrion);

    return Material(
      color: unido ? Tema.acento.withValues(alpha: 0.22) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('anfitrion-${anfitrion.entryId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => lista.unir(lider, unido ? null : anfitrion),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: unido ? Tema.acento : Tema.superficieAlta, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(anfitrion.displayName,
                  style: TextStyle(
                      fontSize: 14,
                      color: unido ? Tema.texto : Tema.textoTenue,
                      fontWeight: unido ? FontWeight.w700 : FontWeight.w400)),
              if (ocupado)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('ya lleva líder',
                      style: TextStyle(color: Tema.aviso, fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El nombre que el jugador le pone a esta unidad.
class _NombrePropio extends StatefulWidget {
  const _NombrePropio({required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  State<_NombrePropio> createState() => _NombrePropioState();
}

class _NombrePropioState extends State<_NombrePropio> {
  late final _control = TextEditingController(text: widget.unidad.customName ?? '');

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Titulo('Nombre propio'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: TextField(
            key: const ValueKey('nombre-propio'),
            controller: _control,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'La Guardia Podrida',
              isDense: true,
            ),
            onSubmitted: (texto) => widget.lista.renombrarUnidad(widget.unidad, texto),
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              widget.lista.renombrarUnidad(widget.unidad, _control.text);
            },
          ),
        ),
      ],
    );
  }
}
