import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import '../widgets/hoja_de_datos.dart';
import 'facciones.dart';

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
        return ColorDeEjercito(
          color: colorDeFaccion(corto(lista.faccion.name)),
          child: _Pantalla(
            lista: lista,
            unidad: unidad,
            avisos: avisos,
            entrada: entrada,
          ),
        );
      },
    );
  }
}

/// La unidad **mirada**, no editada: la hoja de datos de lo que le has puesto.
///
/// Es la otra mitad del interruptor de la lista. Aquí no hay contadores, ni botones de más y
/// menos, ni casillas: el Defiler enseña las armas que le has elegido y el Príncipe Demonio su
/// mejora, igual que una hoja impresa. Es la pantalla de la mesa, donde lo único que se quiere es
/// leer, y donde un toque en un contador estropearía lo que costó montar.
class PantallaDeUnidadEnVisor extends StatelessWidget {
  const PantallaDeUnidadEnVisor({super.key, required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lista,
      builder: (context, _) {
        final entrada = lista.entradaDe(unidad);
        // Lo que lleva puesto, dicho de corrido: es la línea de «unit composition» de la hoja.
        final lleva = unidad.children
            .where((h) => h.name.isNotEmpty && h.name != 'Warlord')
            .map((h) => h.count > 1 ? '${h.count} × ${h.name}' : h.name)
            .toSet()
            .toList();

        return ColorDeEjercito(
          color: colorDeFaccion(corto(lista.faccion.name)),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(unidad.displayName),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: Text('${unidad.points} pts',
                          style: TextStyle(
                              color: ColorDeEjercito.de(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  if (lista.esWarlord(unidad))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Icon(Icons.military_tech,
                              size: 20, color: ColorDeEjercito.de(context)),
                          const SizedBox(width: 8),
                          Text('WARLORD',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: ColorDeEjercito.de(context))),
                        ],
                      ),
                    ),
                  if (lleva.isNotEmpty)
                    _LoQueLleva(nombre: unidad.displayName, piezas: const [], texto: lleva),
                  if (entrada != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: HojaDeDatos(
                        perfiles: lista.hojaDe(unidad),
                        habilidades: lista.habilidadesDe(unidad),
                        cuantas: lista.armasDe(unidad),
                        palabrasClave: entrada.keywords,
                        mejora: lista.mejoraDe(unidad),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Si merece la pena pintar este grupo: algo que elegir, o algo ya puesto.
///
/// Cada detachment declara su propio grupo de mejoras —«Gladius Task Force Enhancements»,
/// «Liberator Assault Group Enhancements»…— y el dataset esconde las opciones de los que no están
/// elegidos, pero el GRUPO seguía apareciendo igual: veinte cajas «0 de 0-1» vacías por cada
/// personaje, de las que solo una —la del destacamento puesto— tenía algo dentro de verdad.
bool _mereceEnsenarse(
    ListaEnCurso lista, Selection dueno, OptionGroup grupo, List<Selection> ofrecidas) {
  if (lista.roster.isModelGroup(dueno, grupo)) return true;
  if (ofrecidas.any((o) => o.groupId == grupo.id)) return true;
  if (dueno.children.any((c) => c.groupId == grupo.id)) return true;
  // Y por si el vacío está más abajo: un grupo sin nada propio pero con un subgrupo que sí
  // ofrece algo —sucede con «Enhancements» de paraguas y sus detachments anidados— se queda.
  return dueno.groups
      .where((g) => g.parentId == grupo.id)
      .any((g) => _mereceEnsenarse(lista, dueno, g, ofrecidas));
}

class _Pantalla extends StatelessWidget {
  const _Pantalla({
    required this.lista,
    required this.unidad,
    required this.avisos,
    required this.entrada,
  });

  final ListaEnCurso lista;
  final Selection unidad;
  final List<Violation> avisos;
  final UnitEntry? entrada;

  @override
  Widget build(BuildContext context) {
    final hoja = entrada;
    return Scaffold(
          appBar: AppBar(
            title: Text(unidad.name),
            actions: [
              Center(
                child: Text('${unidad.points} pts',
                    style: TextStyle(
                        color: ColorDeEjercito.de(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              // Se añade una unidad desde aquí; quitarla tiene que poder hacerse desde aquí.
              // Estaba solo en el deslizar de la lista, que no se ve y no se descubre.
              IconButton(
                key: const ValueKey('borrar-unidad'),
                tooltip: 'Quitar de la lista',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmarBorrado(context, lista, unidad),
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
              if (lista.puedeSerWarlord(unidad))
                _InterruptorDeWarlord(lista: lista, unidad: unidad),
              const _Titulo('Composición y equipo'),
              _NotasDeLaHoja(notas: lista.notasDeEquipoDe(unidad)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _Nodo(lista: lista, nodo: unidad, profundidad: 0),
              ),
              _Union(lista: lista, unidad: unidad),
              _NombrePropio(lista: lista, unidad: unidad),
              // Y debajo, lo que ha quedado: la hoja de datos de lo que lleva puesto, no de todo
              // lo que podría llevar. El Caladius enseña el cañón que le he puesto y no los tres
              // que no; los Plague Marines sin bólters no enseñan el bólter.
              if (hoja != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: HojaDeDatos(
                    perfiles: lista.hojaDe(unidad),
                    habilidades: lista.habilidadesDe(unidad),
                    cuantas: lista.armasDe(unidad),
                    palabrasClave: hoja.keywords,
                    mejora: lista.mejoraDe(unidad),
                  ),
                ),
            ],
          ),
    );
  }
}

Future<void> _confirmarBorrado(
    BuildContext context, ListaEnCurso lista, Selection unidad) async {
  final seguro = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Tema.superficie,
      title: const Text('¿Quitar la unidad?'),
      content: Text('${unidad.displayName} saldrá de la lista.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
      ],
    ),
  );
  if (seguro != true || !context.mounted) return;
  lista.quitarUnidad(unidad);
  if (context.mounted) Navigator.of(context).pop();
}

/// El Warlord: un interruptor, no un contador.
///
/// El dataset lo escribe como una mejora suelta más y por eso salía con su «menos» y su «más»,
/// como si se pudieran tener dos. El ejército tiene uno: se pulsa y se pone aquí, quitándoselo a
/// quien lo tuviera.
///
/// Y hay miniaturas donde ni eso: «Si esta miniatura está en tu ejército, debe ser tu WARLORD» no
/// admite otra respuesta, así que ahí no hay interruptor sino un aviso de que ya lo es.
class _InterruptorDeWarlord extends StatelessWidget {
  const _InterruptorDeWarlord({required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final esWarlord = lista.esWarlord(unidad);
    final obligado = lista.warlordObligado(unidad);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: esWarlord ? acento : Tema.superficie,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: const ValueKey('interruptor-warlord'),
          borderRadius: BorderRadius.circular(6),
          onTap: obligado ? null : () => lista.alternarWarlord(unidad),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: acento.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Icon(esWarlord ? Icons.military_tech : Icons.military_tech_outlined,
                    size: 22, color: esWarlord ? Tema.fondo : acento),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    obligado
                        ? 'WARLORD · lo es por su regla, no se puede cambiar'
                        : esWarlord
                            ? 'WARLORD de este ejército'
                            : 'Hacer Warlord',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: esWarlord ? Tema.fondo : Tema.texto),
                  ),
                ),
                if (obligado)
                  Icon(Icons.lock_outline,
                      size: 17, color: esWarlord ? Tema.fondo : Tema.textoTenue),
              ],
            ),
          ),
        ),
      ),
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
          style: TextStyle(
              color: ColorDeEjercito.de(context),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3)),
    );
  }
}

/// Lo que la hoja de datos dice que se puede cambiar, con sus palabras.
///
/// «For every 5 models in this unit, 1 Terminator's storm bolter can be replaced with one of the
/// following: 1 assault cannon ; 1 heavy flamer ; 1 cyclone missile launcher and 1 storm bolter.»
///
/// Los números de abajo son los que cuentan —salen del dataset, validan y cobran— pero no dicen
/// **qué** se está eligiendo. Esto sí, y es lo que el jugador tiene en la cabeza de leer la hoja.
///
/// No sale en todas: son 493 unidades de las que hay texto que siga valiendo hoy. Donde no lo hay,
/// queda el tope calculado, que es exacto y se actualiza solo. Ver [Dataset.wargearNotesOf].
class _NotasDeLaHoja extends StatelessWidget {
  const _NotasDeLaHoja({required this.notas});

  final List<String> notas;

  @override
  Widget build(BuildContext context) {
    if (notas.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(color: ColorDeEjercito.de(context), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('OPCIONES DE EQUIPO DE LA HOJA',
                style: TextStyle(
                    color: ColorDeEjercito.de(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
          ),
          for (final nota in notas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 5, color: Tema.textoTenue),
                  ),
                  Expanded(
                    child: Text(nota,
                        style: const TextStyle(
                            fontSize: 13, height: 1.4, color: Tema.texto)),
                  ),
                ],
              ),
            ),
        ],
      ),
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
    final raiz = nodo.groups
        .where((g) => g.parentId == null)
        .where((g) => _mereceEnsenarse(lista, nodo, g, ofrecidas))
        .toList();
    final todasSueltas = ofrecidas.where((o) => o.groupId == null).toList();

    // Puesto y ya no ofrecido: equipo de serie que no se puede cambiar.
    final ofrecidosIds = ofrecidas.map((o) => '${o.entryId}|${o.groupId}').toSet();
    final fijos = nodo.children
        .where((h) => !ofrecidosIds.contains('${h.entryId}|${h.groupId}'))
        .toList();

    // El Warlord no es una cantidad: el ejército tiene uno. Sale aparte, como interruptor.
    final sueltas = todasSueltas.where((o) => o.name != 'Warlord').toList();

    // Y el equipo que no se puede cambiar tampoco es una cantidad. Mortarion lleva Lantern,
    // Rotwind y Silence y no hay nada más; un contador ahí —aunque esté bloqueado— ofrece una
    // decisión que no existe. Va como una frase, igual que en la hoja.
    // Solo las que no llevan nada dentro: una pieza fija que a su vez pregunta algo tiene que
    // seguir abriéndose, o se pierde una elección de verdad.
    bool lisa(Selection o) {
      final puesta = nodo.puestaDe(o) ?? o;
      return puesta.groups.isEmpty && lista.opcionesDe(puesta).isEmpty;
    }

    bool clavada(Selection o) =>
        lista.esFija(nodo, o, hayAlternativas: false) && lisa(o);

    final bloqueadas = <Selection>[
      ...sueltas.where(clavada),
      ...fijos.where(lisa),
    ];
    final elegibles = [
      ...sueltas.where((o) => !clavada(o)),
      ...fijos.where((f) => !lisa(f)),
    ];
    final marcables =
        _marcables(lista, nodo, sueltas.where((o) => !clavada(o)).toList(), hayAlternativas: false);

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
        if (bloqueadas.isNotEmpty)
          _LoQueLleva(nombre: nodo.name, piezas: bloqueadas),
        if (elegibles.isNotEmpty)
          _Caja(
            titulo: profundidad == 0 ? 'Equipo' : null,
            hijos: [
              if (marcables.isNotEmpty)
                _Interruptores(
                    lista: lista, dueno: nodo, opciones: marcables, profundidad: profundidad),
              for (final o in elegibles)
                if (!marcables.contains(o))
                  _Fila(
                      lista: lista,
                      dueno: nodo,
                      opcion: o,
                      // Sin grupo cada pieza va por su cuenta: no hay nada que ponerle en su lugar.
                      hayAlternativas: false,
                      profundidad: profundidad,
                      fijo: !ofrecidosIds.contains('${o.entryId}|${o.groupId}')),
            ],
          ),
      ],
    );
  }
}

/// Lo que la miniatura lleva y no se puede cambiar, dicho como lo dice la hoja.
///
/// «Mortarion equipped with: Lantern, Rotwind and Silence». Eso no es una decisión: es lo que hay,
/// y pintarlo con un contador —aunque esté bloqueado y con su candado— ofrece algo que no existe.
/// Va como una frase, que es además donde el jugador la busca.
class _LoQueLleva extends StatelessWidget {
  const _LoQueLleva({required this.nombre, required this.piezas, this.texto});

  final String nombre;
  final List<Selection> piezas;

  /// Los nombres ya hechos, cuando quien llama los tiene y no las selecciones.
  final List<String>? texto;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final nombres = <String>[];
    for (final n in texto ?? const <String>[]) {
      if (!nombres.contains(n)) nombres.add(n);
    }
    for (final p in piezas) {
      final suyo = p.count > 1 ? '${p.count} × ${p.name}' : p.name;
      if (!nombres.contains(suyo)) nombres.add(suyo);
    }
    if (nombres.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: acento.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: acento.withValues(alpha: 0.22),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('EQUIPO',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: acento)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Text('$nombre va con: ${_enumera(nombres)}',
                style: const TextStyle(fontSize: 14.5, height: 1.35, color: Tema.texto)),
          ),
        ],
      ),
    );
  }

  static String _enumera(List<String> nombres) {
    if (nombres.length == 1) return nombres.first;
    return '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
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
    final anidados = dueno.groups
        .where((g) => g.parentId == grupo.id)
        .where((g) => _mereceEnsenarse(lista, dueno, g, ofrecidas))
        .toList();
    final unaSola = uso.maximo == 1;
    final obligatorio = (uso.minimo ?? 0) > 0;
    final incumple = (uso.minimo != null && uso.puestas < uso.minimo!) ||
        (uso.maximo != null && uso.puestas > uso.maximo!);

    // Un grupo cuyas opciones son **miniaturas** es una escuadra, y eso se edita de otra manera:
    // arriba cuántas hay, y debajo a cuántas de ellas les cambias el arma. Ver [_Escuadra].
    if (lista.esGrupoDeMiniaturas(dueno, grupo)) {
      return _Escuadra(
        lista: lista,
        dueno: dueno,
        grupo: grupo,
        ofrecidas: ofrecidas,
        uso: uso,
        miniaturas: lista.miniaturasDe(dueno, grupo),
        incumple: incumple,
      );
    }

    // Y un grupo con techo de más de uno cuyas opciones son **equipo**, no miniaturas, es una
    // sola miniatura repartiendo sus propios acoplamientos: el Dreadnought con dos brazos, el
    // Wraithlord con dos armas pesadas. No son cinco Marines a los que reparto un plasma cada
    // uno —eso sí es un contador—; es UNA miniatura eligiendo qué lleva en cada uno de los suyos,
    // y eso se elige, no se cuenta.
    if (!unaSola &&
        uso.maximo != null &&
        uso.maximo! > 1 &&
        mias.isNotEmpty &&
        mias.every((o) => o.type == 'upgrade')) {
      return _Caja(
        titulo: grupo.name ?? 'Opciones',
        contador: _contador(uso),
        pista: _pista(uso),
        incumple: incumple,
        hijos: [
          _RanurasDeEquipo(lista: lista, dueno: dueno, opciones: mias, uso: uso),
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

    final marcables = unaSola
        ? const <Selection>[]
        : _marcables(lista, dueno, mias, hayAlternativas: uso.maximo != null);

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
        else ...[
          // Una miniatura suelta no cuenta lo que lleva: lo marca. El Havoc launcher del Rhino,
          // el misil del Land Raider, la Ghostglaive del Wraithlord son «lo lleva o no», como
          // el cañón del Defiler, y no un «0 / 1» con más y menos.
          if (marcables.isNotEmpty)
            _Interruptores(
                lista: lista, dueno: dueno, opciones: marcables, profundidad: profundidad),
          for (final o in mias)
            if (!marcables.contains(o))
              _Fila(
                  lista: lista,
                  dueno: dueno,
                  opcion: o,
                  // Alternativas de verdad, no solo «hay más de una en el grupo»: el Biologus
                  // Putrifier lleva Hyper blight grenades, Injector pistol y Plague knives a la
                  // vez, en el mismo grupo «Wargear», sin techo que las haga competir entre sí.
                  // Contando «más de una opción» como alternativas, el «−» las dejaba bajar a
                  // cero como si sobrase elegir entre ellas, cuando las tres son fijas.
                  hayAlternativas: uso.maximo != null,
                  profundidad: profundidad),
        ],
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

/// Una escuadra: cuántas miniaturas tiene y a cuántas de ellas les cambias el arma.
///
/// Son dos decisiones distintas y el dataset las mezcla en el mismo montón, que es de donde venía
/// el lío. Una escuadra de Plague Marines son «9 miniaturas», y aparte «a 2 de ellas les quitas el
/// bólter y les pones un plasma». Pintándolo todo junto pasaban dos cosas: no se sabía cuántas
/// miniaturas había sin sumar de cabeza, y al llegar al máximo **no se podía asignar ni un arma**,
/// porque el hueco ya lo ocupaba la propia miniatura a la que había que cambiársela.
///
/// Aquí arriba va el tamaño y debajo los cambios de arma, cada uno empezando en cero. Poner uno no
/// hace crecer la escuadra: se lo quita al relleno. El techo de cada arma es el **efectivo**, así
/// que sube solo al crecer la escuadra, que es como el dataset escribe «una por cada cinco
/// miniaturas»: no con esa frase, sino con un modifier que cambia el techo según cuántas haya.
/// Lo que lleva una sola miniatura en sus propios acoplamientos, elegido y no contado.
///
/// El Contemptor-Achillus lleva «exactamente 2» de entre tres armas: dos Infernus incinerator,
/// dos Lastrum storm bolter, una de cada… BSData lo escribe como un techo de grupo —«máximo 2»,
/// y cada arma con su propio «máximo 2»—, y contado a lo bruto eso sale como tres contadores con
/// más y menos, que es justo cómo se ve una escuadra repartiendo armas especiales. Pero aquí no
/// hay cinco miniaturas: hay una, con dos sitios donde poner un arma. Cada acoplamiento se pinta
/// aparte, y en cada uno se elige, no se suma.
class _RanurasDeEquipo extends StatelessWidget {
  const _RanurasDeEquipo({
    required this.lista,
    required this.dueno,
    required this.opciones,
    required this.uso,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final List<Selection> opciones;
  final ({int puestas, int? minimo, int? maximo}) uso;

  @override
  Widget build(BuildContext context) {
    // Lo puesto ahora, aplanado: cada copia de cada arma es una ranura ocupada. El orden es el
    // de la lista de opciones, así que es estable de una pulsación a la siguiente.
    final ocupadas = <Selection>[
      for (final o in opciones)
        for (var i = 0; i < dueno.cuantasDe(o); i++) o,
    ];
    final total = uso.maximo!;
    final obligatorias = uso.minimo ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UnaRanura(
              lista: lista,
              dueno: dueno,
              opciones: opciones,
              actual: i < ocupadas.length ? ocupadas[i] : null,
              numero: i + 1,
              deCuantas: total,
              // Se puede dejar vacía si esta ranura pasa del mínimo exigido.
              vaciable: i >= obligatorias,
            ),
          ),
      ],
    );
  }
}

/// Un acoplamiento: lo que lleva ahora y con qué se puede cambiar.
class _UnaRanura extends StatelessWidget {
  const _UnaRanura({
    required this.lista,
    required this.dueno,
    required this.opciones,
    required this.actual,
    required this.numero,
    required this.deCuantas,
    required this.vaciable,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final List<Selection> opciones;
  final Selection? actual;
  final int numero;
  final int deCuantas;
  final bool vaciable;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    return Container(
      decoration: BoxDecoration(
        color: Tema.fondo,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(deCuantas > 1 ? 'Acoplamiento $numero' : 'Equipo',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: acento)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in opciones)
                _BotonDeRanura(
                  lista: lista,
                  dueno: dueno,
                  opcion: o,
                  elegida: actual?.entryId == o.entryId,
                  onPulsar: () {
                    if (actual?.entryId == o.entryId) {
                      if (vaciable) lista.vaciarRanura(dueno, o);
                    } else {
                      lista.cambiarRanura(dueno, actual, o);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotonDeRanura extends StatelessWidget {
  const _BotonDeRanura({
    required this.lista,
    required this.dueno,
    required this.opcion,
    required this.elegida,
    required this.onPulsar,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;
  final bool elegida;
  final VoidCallback onPulsar;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final puntos = opcion.basePointsEach;
    return Material(
      color: elegida ? acento.withValues(alpha: 0.26) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('ranura-${opcion.entryId}-${opcion.groupId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: onPulsar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: elegida ? acento : Tema.superficieAlta, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(opcion.name,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      color: elegida ? Tema.texto : Tema.textoTenue,
                      fontWeight: elegida ? FontWeight.w700 : FontWeight.w400)),
              if (puntos > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child:
                      Text('+$puntos pts', style: TextStyle(color: acento, fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Escuadra extends StatelessWidget {
  const _Escuadra({
    required this.lista,
    required this.dueno,
    required this.grupo,
    required this.ofrecidas,
    required this.uso,
    required this.miniaturas,
    required this.incumple,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;
  final List<Selection> ofrecidas;

  /// Lo que se puede tocar: el grupo. Manda en los botones.
  final ({int puestas, int? minimo, int? maximo}) uso;

  /// Lo que hay: el grupo más el sargento. Manda en el número que se lee.
  final ({int puestas, int? minimo, int? maximo}) miniaturas;
  final bool incumple;

  @override
  Widget build(BuildContext context) {
    final relleno = lista.rellenoDe(dueno, grupo);
    // Todo lo que sale de esta escuadra, esté en el grupo o en un subgrupo suyo: las armas
    // especiales cuelgan de «Special weapons» pero las llevan las mismas miniaturas.
    final suyas = ofrecidas
        .where((o) => o.type == 'model')
        .where((o) => lista.grupoDeMiniaturasDe(dueno, o)?.id == grupo.id)
        .toList();
    final cambios = suyas.where((o) => o.entryId != relleno?.entryId).toList();

    // Por subgrupo, que es donde el dataset pone los topes compartidos: «Special weapons, 2».
    final porSubgrupo = <String?, List<Selection>>{};
    for (final o in cambios) {
      porSubgrupo.putIfAbsent(o.groupId == grupo.id ? null : o.groupId, () => []).add(o);
    }

    return _Caja(
      titulo: grupo.name ?? 'Escuadra',
      contador: _contador(),
      pista: _pista(),
      incumple: incumple,
      hijos: [
        // El grupo del sargento no lleva contador propio: sus miniaturas ya las cuenta la barra de
        // la escuadra, y pintar dos contadores era leer una escuadra de diez como «9» y «1».
        if (!lista.seCuentaEnLaEscuadra(dueno, grupo))
          _BarraDeMiniaturas(
            lista: lista,
            dueno: dueno,
            grupo: grupo,
            uso: miniaturas,
            fija: (uso.minimo ?? 0) == (uso.maximo ?? -1),
          ),
        _Composicion(lista: lista, dueno: dueno, grupo: grupo),
        for (final entrada in porSubgrupo.entries) ...[
          _CabeceraDeCambios(
            lista: lista,
            dueno: dueno,
            grupo: grupo,
            subgrupo: entrada.key == null
                ? null
                : dueno.groups.where((g) => g.id == entrada.key).firstOrNull,
            armas: entrada.value,
          ),
          for (final arma in entrada.value)
            _CambioDeArma(lista: lista, dueno: dueno, opcion: arma),
        ],
      ],
    );
  }

  String? _contador() {
    final m = miniaturas;
    if (m.minimo == null && m.maximo == null) return null;
    if (m.minimo == m.maximo) return '${m.puestas} de ${m.maximo}';
    return '${m.puestas} de ${m.minimo ?? 0}-${m.maximo?.toString() ?? "∞"}';
  }

  String? _pista() {
    final m = miniaturas;
    if (m.minimo != null && m.minimo == m.maximo) {
      return 'Escuadra fija de ${m.minimo} miniaturas';
    }
    if (m.minimo != null && m.maximo != null) {
      return 'De ${m.minimo} a ${m.maximo} miniaturas';
    }
    if (m.maximo != null) return 'Hasta ${m.maximo} miniaturas';
    if (m.minimo != null) return 'Mínimo ${m.minimo} miniaturas';
    return null;
  }
}

/// Con qué va la escuadra ahora mismo, miniatura a miniatura.
///
/// «9 Plague Marines con Boltgun y Plague knives» mientras no se toque nada, y en cuanto se
/// reparten armas, una línea por cada grupo distinto: es lo que hay que leer para saber si la
/// escuadra está montada como se quería.
class _Composicion extends StatelessWidget {
  const _Composicion({required this.lista, required this.dueno, required this.grupo});

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;

  @override
  Widget build(BuildContext context) {
    final puestas = dueno.children
        .where((c) => c.type == 'model')
        .where((c) => lista.grupoDeMiniaturasDe(dueno, c)?.id == grupo.id)
        .where((c) => c.count > 0)
        .toList();
    if (puestas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in puestas)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('${c.count} × ${c.name}',
                  style: const TextStyle(fontSize: 13.5, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

/// La frase que dice qué se puede cambiar y a cuántas miniaturas.
///
/// El número es el **efectivo de ahora**, no el que trae escrito el dataset: la hoja dice «una por
/// cada cinco miniaturas» y el dataset lo escribe como un techo que sube solo al crecer la
/// escuadra. Enseñar la cuenta ya hecha es lo que evita tener que hacerla.
class _CabeceraDeCambios extends StatelessWidget {
  const _CabeceraDeCambios({
    required this.lista,
    required this.dueno,
    required this.grupo,
    required this.subgrupo,
    required this.armas,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;
  final OptionGroup? subgrupo;
  final List<Selection> armas;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final tope = subgrupo != null
        ? lista.usoDeGrupo(dueno, subgrupo!).maximo
        : armas
            .map((a) => lista.topeDeArma(dueno, a))
            .whereType<int>()
            .fold<int?>(null, (t, v) => t == null || v > t ? v : t);

    final texto = tope == null
        ? 'Cambia el arma de las miniaturas que quieras'
        : tope == 1
            ? 'Cambia el arma de 1 miniatura'
            : 'Cambia el arma de hasta $tope miniaturas';

    return Container(
      width: double.infinity,
      color: acento.withValues(alpha: 0.22),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Text(
          subgrupo?.name == null ? texto : '${subgrupo!.name} · $texto',
          style: const TextStyle(fontSize: 12.5, color: Tema.texto, height: 1.3)),
    );
  }
}

/// Una fila de cambio de arma: «0 × Plasma gun», con menos y más.
///
/// Y si lo que se pone **pregunta a su vez** —el «Terminator w/ Heavy Weapon» no dice cuál, hay
/// que elegir entre assault cannon, heavy flamer y cyclone—, la fila se despliega y enseña esa
/// elección dentro. Sin eso, poner uno dejaba la unidad con un hueco obligatorio que no había
/// forma de rellenar desde ninguna pantalla.
class _CambioDeArma extends StatelessWidget {
  const _CambioDeArma(
      {required this.lista, required this.dueno, required this.opcion});

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;

  @override
  Widget build(BuildContext context) {
    final instancias = lista.instanciasDe(dueno, opcion);
    final pregunta =
        instancias.isNotEmpty && lista.preguntaQueArma(instancias.first);
    final fila = _fila(context);
    if (!pregunta) return fila;

    // Un cuadro por miniatura, no uno con un «×2». Dos armas pesadas son dos Terminators, y cada
    // uno elige la suya: una puede llevar cyclone y el otro assault cannon. Con un solo cuadro la
    // elección era una y valía para los dos.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fila,
        for (var i = 0; i < instancias.length; i++)
          _MiniaturaQueElige(
            lista: lista,
            dueno: dueno,
            instancia: instancias[i],
            numero: i + 1,
            deCuantas: instancias.length,
          ),
      ],
    );
  }

  Widget _fila(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final cuantas = dueno.cuantasDe(opcion);
    final tope = lista.topeDeArma(dueno, opcion);
    final puntos = opcion.basePointsEach;

    return Padding(
      key: ValueKey('arma-${opcion.entryId}'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          _BotonGrande(
            icono: Icons.remove,
            color: acento,
            activo: cuantas > 0,
            onPressed: () => lista.devolverArma(dueno, opcion),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Tema.fondo,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Text('$cuantas × ',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cuantas > 0 ? acento : Tema.textoTenue)),
                  Expanded(
                    child: Text(_sinPrefijo(opcion.name),
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            color: cuantas > 0 ? Tema.texto : Tema.textoTenue)),
                  ),
                  if (puntos > 0)
                    Text('+$puntos',
                        style: TextStyle(color: acento, fontSize: 12)),
                  if (tope != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('máx $tope',
                          style: const TextStyle(color: Tema.textoTenue, fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          _BotonGrande(
            icono: Icons.add,
            color: acento,
            activo: lista.sePuedeAsignar(dueno, opcion),
            onPressed: () => lista.asignarArma(dueno, opcion),
          ),
        ],
      ),
    );
  }
}

/// El dataset llama a las miniaturas «Plague Marine w/ plasma gun»; en una lista de cambios de
/// arma lo que importa es el arma, y repetir el nombre de la unidad en cada fila es ruido.
String _sinPrefijo(String nombre) {
  final corte = nombre.indexOf(RegExp(r'\bw/\s*'));
  if (corte < 0) return nombre;
  final arma = nombre.substring(corte).replaceFirst(RegExp(r'^w/\s*'), '').trim();
  return arma.isEmpty ? nombre : '${arma[0].toUpperCase()}${arma.substring(1)}';
}

/// Una de las miniaturas que llevan un arma que hay que elegir, con su elección dentro.
///
/// Cuando una escuadra puede cambiar dos armas, son **dos miniaturas** y cada una elige la suya.
/// Enseñarlo como «2 × Terminator w/ Heavy Weapon» con un solo desplegable dentro obligaba a que
/// las dos llevaran lo mismo, que es justo lo contrario de lo que dice la hoja.
class _MiniaturaQueElige extends StatelessWidget {
  const _MiniaturaQueElige({
    required this.lista,
    required this.dueno,
    required this.instancia,
    required this.numero,
    required this.deCuantas,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection instancia;
  final int numero;
  final int deCuantas;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final avisos = lista.incumplimientosDe(instancia).length;
    // Lo que lleva ahora mismo, que es lo que hay que leer de un vistazo para saber cuál es cuál.
    final lleva = instancia.children
        .where((c) => c.groupId != null)
        .map((c) => _sinPrefijo(c.name))
        .join(', ');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 8, 6),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: acento.withValues(alpha: 0.6), width: 3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('miniatura-${instancia.entryId}-$numero'),
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: acento.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(deCuantas > 1 ? 'Miniatura $numero' : 'Esta miniatura',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: acento)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(lleva.isEmpty ? 'sin elegir' : lleva,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.2,
                        color: lleva.isEmpty ? Tema.aviso : Tema.texto)),
              ),
              _BotonGrande(
                icono: Icons.close,
                color: acento,
                activo: true,
                onPressed: () => lista.devolverArmaDe(dueno, instancia),
              ),
            ],
          ),
          subtitle: avisos == 0
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                      avisos == 1 ? 'falta algo por elegir' : '$avisos cosas por elegir',
                      style: const TextStyle(color: Tema.aviso, fontSize: 11.5)),
                ),
          children: [_Nodo(lista: lista, nodo: instancia, profundidad: 1)],
        ),
      ),
    );
  }
}

/// El contador de miniaturas de una escuadra: cuántas hay, y menos y más.
///
/// Uno solo para toda la unidad, como en la hoja: primero se decide si son cinco o diez y después
/// con qué van. El «+» mete un soldado raso —no el sargento ni el arma especial—, que es quien de
/// verdad hace crecer una escuadra; el «−» quita del montón más grande que se pueda tocar.
///
/// Cuando el dataset no deja elegir el tamaño —«90 puntos son 10 miniaturas y punto»— no hay
/// botones: se enseña el número y ya, porque ahí no hay nada que decidir.
class _BarraDeMiniaturas extends StatelessWidget {
  const _BarraDeMiniaturas({
    required this.lista,
    required this.dueno,
    required this.grupo,
    required this.uso,
    required this.fija,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final OptionGroup grupo;
  final ({int puestas, int? minimo, int? maximo}) uso;
  final bool fija;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    // El nombre del grupo, sin el «4-5» con que el dataset lo encabeza: el número lo pone el
    // contador y repetirlo despista. Queda «9 Terminators», como en la hoja.
    final nombre = (grupo.name ?? 'miniaturas')
        .replaceFirst(RegExp(r'^\d+\s*-\s*\d+\s*'), '')
        .trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: Tema.fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: acento.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          if (!fija)
            _BotonGrande(
              key: const ValueKey('quitar-miniatura'),
              icono: Icons.remove,
              color: acento,
              activo: lista.sePuedeQuitarMiniatura(dueno, grupo),
              onPressed: () => lista.quitarMiniatura(dueno, grupo),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('${uso.puestas} $nombre',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          if (!fija)
            _BotonGrande(
              key: const ValueKey('anadir-miniatura'),
              icono: Icons.add,
              color: acento,
              activo: lista.cabeOtraMiniatura(dueno, grupo),
              onPressed: () => lista.anadirMiniatura(dueno, grupo),
            ),
        ],
      ),
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({
    super.key,
    required this.icono,
    required this.color,
    required this.activo,
    required this.onPressed,
  });

  final IconData icono;
  final Color color;
  final bool activo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? color : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: activo ? onPressed : null,
        child: SizedBox(
          width: 46,
          height: 38,
          child: Icon(icono,
              size: 22,
              color: activo
                  ? (color.computeLuminance() > 0.45
                      ? const Color(0xFF14120F)
                      : Colors.white)
                  : Tema.textoTenue.withValues(alpha: 0.4)),
        ),
      ),
    );
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
    final acento = ColorDeEjercito.de(context);
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
                color: acento.withValues(alpha: 0.9),
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
                                color: incumple ? Tema.aviso : _sobre(acento),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        if (pista != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(pista!,
                                style: TextStyle(
                                    color: _sobre(acento).withValues(alpha: 0.85),
                                    fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ),
                  if (contador != null)
                    Text(contador!,
                        style: TextStyle(
                            color: incumple ? Tema.aviso : _sobre(acento),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
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
/// Las opciones que en esta miniatura se marcan en vez de contarse.
///
/// Solo en una miniatura suelta, solo lo que se puede quitar y poner, y solo lo que como mucho
/// cabe una vez: si el dataset deja llevar dos de lo mismo, eso sí es una cantidad.
List<Selection> _marcables(ListaEnCurso lista, Selection dueno, List<Selection> opciones,
    {required bool hayAlternativas}) {
  if (!lista.esUnaMiniatura(dueno)) return const [];
  return [
    for (final o in opciones)
      if (!lista.esFija(dueno, o, hayAlternativas: hayAlternativas) &&
          (lista.topeDeArma(dueno, o) ?? 1) <= 1)
        o,
  ];
}

/// Lo que una miniatura suelta puede llevar o no, como botones que se marcan.
///
/// Lo marcado que a su vez pregunta algo —un arma con sus mejoras— se abre debajo.
class _Interruptores extends StatelessWidget {
  const _Interruptores({
    required this.lista,
    required this.dueno,
    required this.opciones,
    required this.profundidad,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final List<Selection> opciones;
  final int profundidad;

  @override
  Widget build(BuildContext context) {
    final conDentro = [
      for (final o in opciones)
        if (dueno.puestaDe(o) case final puesta?)
          if (puesta.groups.isNotEmpty || lista.opcionesDe(puesta).isNotEmpty) puesta,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in opciones)
                _BotonDeOpcion(
                  lista: lista,
                  dueno: dueno,
                  opcion: o,
                  obligatorio: false,
                  activo: dueno.puestaDe(o) != null
                      ? lista.sePuedeQuitar(dueno, o)
                      : lista.cabeOtra(dueno, o),
                ),
            ],
          ),
        ),
        for (final puesta in conDentro)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _Nodo(lista: lista, nodo: puesta, profundidad: profundidad + 1),
          ),
      ],
    );
  }
}

class _BotonDeOpcion extends StatelessWidget {
  const _BotonDeOpcion({
    required this.lista,
    required this.dueno,
    required this.opcion,
    required this.obligatorio,
    this.activo = true,
  });

  final ListaEnCurso lista;
  final Selection dueno;
  final Selection opcion;
  final bool obligatorio;

  /// Si se puede tocar: poner lo que ya no cabe, o quitar lo que el dataset exige, no.
  final bool activo;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final puesta = dueno.puestaDe(opcion) != null;
    final puntos = opcion.basePointsEach;
    final mejora = opcion.baseCosts.containsKey(enhancementsCostTypeId);

    return Material(
      color: puesta ? acento.withValues(alpha: 0.26) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('opcion-${opcion.entryId}-${opcion.groupId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: !activo
            ? null
            : () => obligatorio
                ? lista.elegirOpcion(dueno, opcion)
                : lista.alternarOpcion(dueno, opcion),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: puesta ? acento : Tema.superficieAlta, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(opcion.name,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: puesta
                          ? Tema.texto
                          : activo
                              ? Tema.textoTenue
                              : Tema.textoTenue.withValues(alpha: 0.45),
                      fontWeight: puesta ? FontWeight.w700 : FontWeight.w400)),
              if (puntos > 0 || mejora)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      [if (puntos > 0) '+$puntos pts', if (mejora) 'mejora'].join(' · '),
                      style: TextStyle(color: acento, fontSize: 11)),
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
              style: TextStyle(color: ColorDeEjercito.de(context), fontSize: 11),
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
                  color: cuantas > 0 ? ColorDeEjercito.de(context) : Tema.textoTenue)),
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

/// El color de texto que se lee sobre una barra de ese tono.
Color _sobre(Color fondo) =>
    fondo.computeLuminance() > 0.45 ? const Color(0xFF14120F) : Colors.white;

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
                  leading: Icon(Icons.link, size: 18, color: ColorDeEjercito.de(context)),
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
    final acento = ColorDeEjercito.de(context);
    final unido = lider.attachedTo == anfitrion;
    // Si unirse rompería un límite de la unidad —cuántos Leader caben, una sola mejora— se enseña
    // igual, deshabilitada y con el motivo: es lo que el jugador necesita para decidir.
    final motivo = lista.motivoParaUnir(lider, anfitrion);
    final bloqueado = motivo != null;

    return Material(
      color: unido ? acento.withValues(alpha: 0.26) : Tema.superficieAlta,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('anfitrion-${anfitrion.entryId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: bloqueado ? null : () => lista.unir(lider, unido ? null : anfitrion),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: unido ? acento : Tema.superficieAlta, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(anfitrion.displayName,
                  style: TextStyle(
                      fontSize: 14,
                      color: unido
                          ? Tema.texto
                          : bloqueado
                              ? Tema.textoTenue.withValues(alpha: 0.5)
                              : Tema.textoTenue,
                      fontWeight: unido ? FontWeight.w700 : FontWeight.w400)),
              if (motivo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(motivo,
                        style: const TextStyle(color: Tema.aviso, fontSize: 11)),
                  ),
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
