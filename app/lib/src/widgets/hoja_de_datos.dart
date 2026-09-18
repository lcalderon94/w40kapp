import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import 'texto_reglas.dart';

/// La banda con el nombre de la unidad, como el encabezado de la hoja impresa.
class BandaDeUnidad extends StatelessWidget {
  const BandaDeUnidad({
    super.key,
    required this.nombre,
    this.rol,
    this.puntos,
    this.subtitulo,
  });

  final String nombre;
  final String? rol;
  final int? puntos;

  /// El nombre de la hoja de datos cuando la unidad lleva uno propio.
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Tema.acento.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: Tema.acento, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(nombre.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: 0.3)),
              ),
              if (puntos != null)
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Tema.fondo,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Tema.acento, width: 1.5),
                  ),
                  child: Text('$puntos',
                      style: const TextStyle(
                          color: Tema.acento, fontSize: 17, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          if (subtitulo != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitulo!,
                  style: const TextStyle(color: Tema.textoTenue, fontSize: 13)),
            ),
          if (rol != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(rol!.toUpperCase(),
                  style: const TextStyle(
                      color: Tema.textoTenue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ),
        ],
      ),
    );
  }
}

/// La hoja de datos de una unidad, con el mismo orden y las mismas partes que la impresa.
///
/// Va aquí y no en una pantalla porque hace falta en tres sitios: al consultar una unidad del
/// catálogo, al mirarla antes de añadirla y al equipar una de la lista, donde ver y editar tienen
/// que estar juntos.
class HojaDeDatos extends StatelessWidget {
  const HojaDeDatos({
    super.key,
    required this.perfiles,
    required this.palabrasClave,
    this.habilidades = const [],
    this.cuantas = const {},
    this.encabezado,
  });

  final List<Profile> perfiles;
  final List<String> palabrasClave;

  /// Las líneas CORE y FACTION: las habilidades que son reglas del reglamento.
  final List<Ability> habilidades;

  /// Cuántas miniaturas llevan cada arma, para el número de la izquierda.
  final Map<String, int> cuantas;

  /// Lo que va antes de la línea de características, si hace falta.
  final Widget? encabezado;

  @override
  Widget build(BuildContext context) {
    final porTipo = <String, List<Profile>>{};
    for (final perfil in perfiles) {
      porTipo.putIfAbsent(perfil.typeName, () => []).add(perfil);
    }
    final caracteristicas = porTipo.remove('Unit') ?? const <Profile>[];
    final propias = porTipo.remove('Abilities') ?? const <Profile>[];
    final aDistancia = porTipo.remove('Ranged Weapons') ?? const <Profile>[];
    final cuerpoACuerpo = porTipo.remove('Melee Weapons') ?? const <Profile>[];

    final core = habilidades.where((h) => h.isCore).toList();
    final faccion = habilidades.where((h) => h.isFaction).toList();
    final invulnerable = Invulnerable.of(perfiles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (encabezado != null) encabezado!,
        for (final perfil in caracteristicas)
          _LineaDeCaracteristicas(perfil, invulnerable: invulnerable),
        if (aDistancia.isNotEmpty) ...[
          const _Seccion('Armas a distancia'),
          _TablaDeArmas(aDistancia, columnaDeHabilidad: 'BS', cuantas: cuantas),
        ],
        if (cuerpoACuerpo.isNotEmpty) ...[
          const _Seccion('Armas de cuerpo a cuerpo'),
          _TablaDeArmas(cuerpoACuerpo, columnaDeHabilidad: 'WS', cuantas: cuantas),
        ],
        if (core.isNotEmpty || faccion.isNotEmpty || propias.isNotEmpty) ...[
          const _Seccion('Habilidades'),
          // CORE y FACTION van arriba y en una línea, como en la hoja: son las que dicen si la
          // unidad hace despliegue rápido, si es un líder o qué pasa cuando explota. Cada una se
          // toca y se explica sola; el reglamento lo trae la app.
          if (core.isNotEmpty) _LineaDeHabilidades('CORE', core),
          if (faccion.isNotEmpty) _LineaDeHabilidades('FACTION', faccion),
          for (final habilidad in propias) _Habilidad(habilidad),
        ],
        for (final entrada in porTipo.entries) ...[
          _Seccion(entrada.key),
          for (final perfil in entrada.value) _Habilidad(perfil),
        ],
        if (palabrasClave.isNotEmpty) ...[
          const _Seccion('Palabras clave'),
          _Palabras(palabrasClave.where((p) => !p.startsWith('Faction:')).toList()),
          if (palabrasClave.any((p) => p.startsWith('Faction:'))) ...[
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 6),
              child: Text('PALABRAS CLAVE DE FACCIÓN',
                  style: TextStyle(
                      color: Tema.textoTenue,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
            ),
            _Palabras([
              for (final p in palabrasClave)
                if (p.startsWith('Faction:')) p.substring('Faction:'.length).trim(),
            ]),
          ],
        ],
      ],
    );
  }
}

/// Abre la explicación de una regla del reglamento, si la app la tiene.
///
/// Es lo que evita salir de la ficha a buscar qué hace [SUSTAINED HITS] o Deep Strike. Si la regla
/// no está en el reglamento básico —una habilidad de facción— se enseña lo que traiga la hoja.
void mostrarRegla(BuildContext context, String nombre, {String? texto}) {
  final regla = Datos.de(context).ruleNamed(nombre);
  final cuerpo = regla?.description ?? texto;
  if (cuerpo == null || cuerpo.trim().isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Tema.superficie,
      title: Text(regla?.name ?? nombre,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: TextoDeRegla(cuerpo, estilo: const TextStyle(fontSize: 15, height: 1.45)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar', style: TextStyle(color: Tema.acento))),
      ],
    ),
  );
}

/// Una palabra clave del reglamento que se toca y se explica.
class ClaveTocable extends StatelessWidget {
  const ClaveTocable(this.texto, {super.key, this.descripcion, this.estilo});

  final String texto;
  final String? descripcion;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    final hay = Datos.de(context).ruleNamed(texto) != null ||
        (descripcion != null && descripcion!.trim().isNotEmpty);
    return InkWell(
      key: ValueKey('clave-$texto'),
      onTap: hay ? () => mostrarRegla(context, texto, texto: descripcion) : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Tema.acento.withValues(alpha: hay ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto.toUpperCase(),
                style: estilo ??
                    const TextStyle(
                        color: Tema.acento,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
            if (hay)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.help_outline, size: 12, color: Tema.acento),
              ),
          ],
        ),
      ),
    );
  }
}

/// «CORE: Deadly Demise D3, Deep Strike, Lone Operative», y cada una se toca.
class _LineaDeHabilidades extends StatelessWidget {
  const _LineaDeHabilidades(this.etiqueta, this.habilidades);

  final String etiqueta;
  final List<Ability> habilidades;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: Text('$etiqueta:',
                style: const TextStyle(
                    color: Tema.textoTenue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final habilidad in habilidades)
                  ClaveTocable(habilidad.name, descripcion: habilidad.description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaDeCaracteristicas extends StatelessWidget {
  const _LineaDeCaracteristicas(this.perfil, {this.invulnerable});

  final Profile perfil;
  final Invulnerable? invulnerable;

  @override
  Widget build(BuildContext context) {
    final valores = {...perfil.characteristics};
    final enLinea = valores.remove('InSv');
    final invSv = enLinea ?? invulnerable?.value;
    final condicionada = invulnerable?.isConditional ?? (invSv?.contains('*') ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final caracteristica in valores.entries)
                  _Caja(etiqueta: caracteristica.key, valor: caracteristica.value),
              ],
            ),
          ),
        ),
        // La salvación invulnerable va en su propia fila y con su nombre escrito, como en la hoja
        // impresa: no es una característica más de la línea y quien la busca la busca por nombre.
        if (invSv != null && invSv.trim().isNotEmpty && invSv.trim() != '-')
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Tema.fondo,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    border: Border.all(color: Tema.acento, width: 1.5),
                  ),
                  child: Text(invSv.trim(),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, height: 1)),
                ),
                Flexible(
                  child: Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Tema.acento.withValues(alpha: 0.14),
                      borderRadius:
                          const BorderRadius.horizontal(right: Radius.circular(6)),
                    ),
                    child: Text(
                        condicionada && invulnerable != null
                            ? 'SALVACIÓN INVULNERABLE · solo contra ${invulnerable!.scope}'
                            : 'SALVACIÓN INVULNERABLE',
                        style: const TextStyle(
                            color: Tema.acento,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          Text(etiqueta.toUpperCase(),
              style: const TextStyle(
                  color: Tema.textoTenue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Tema.fondo,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Tema.superficieAlta, width: 1.5),
            ),
            child: Text(valor.trim(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
          ),
        ],
      ),
    );
  }
}

class _Habilidad extends StatelessWidget {
  const _Habilidad(this.perfil);

  final Profile perfil;

  @override
  Widget build(BuildContext context) {
    final texto = perfil.description ?? perfil.characteristics.values.join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(perfil.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          TextoDeRegla(texto, estilo: const TextStyle(fontSize: 15, height: 1.4)),
        ],
      ),
    );
  }
}

/// Las armas, con cuántas miniaturas las llevan y sus palabras clave tocables.
class _TablaDeArmas extends StatelessWidget {
  const _TablaDeArmas(this.armas,
      {required this.columnaDeHabilidad, this.cuantas = const {}});

  final List<Profile> armas;
  final String columnaDeHabilidad;
  final Map<String, int> cuantas;

  static const _columnas = ['Range', 'A', 'S', 'AP', 'D'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final arma in armas)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // El número de la izquierda, como en la hoja impresa: «4 Guardian spear».
                    if ((cuantas[arma.name] ?? 0) > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 1),
                        child: Text('${cuantas[arma.name]}',
                            style: const TextStyle(
                                color: Tema.acento,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    Expanded(
                      child: Text(_sinFlecha(arma.name),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final columna in [
                        _columnas.first,
                        columnaDeHabilidad,
                        ..._columnas.skip(1),
                      ])
                        _Celda(nombre: columna, valor: arma.characteristics[columna] ?? '—'),
                    ],
                  ),
                ),
                if ((arma.characteristics['Keywords'] ?? '').isNotEmpty &&
                    arma.characteristics['Keywords'] != '-')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final clave in arma.characteristics['Keywords']!.split(','))
                          if (clave.trim().isNotEmpty) ClaveTocable(clave.trim()),
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

class _Celda extends StatelessWidget {
  const _Celda({required this.nombre, required this.valor});

  final String nombre;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        children: [
          Text(nombre.toUpperCase(),
              style: const TextStyle(
                  color: Tema.textoTenue,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Container(
            constraints: const BoxConstraints(minWidth: 46, minHeight: 38),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Tema.superficie,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(valor,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1)),
          ),
        ],
      ),
    );
  }
}

class _Palabras extends StatelessWidget {
  const _Palabras(this.palabras);

  final List<String> palabras;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final palabra in palabras)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Tema.superficieAlta,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(palabra.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        color: Tema.acento.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: Tema.acento, width: 3)),
      ),
      child: Text(titulo.toUpperCase(),
          style: const TextStyle(
              color: Tema.acento,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2)),
    );
  }
}

/// El dataset marca los subperfiles de un arma con «➤». En la ficha sobra.
String _sinFlecha(String nombre) => nombre.replaceFirst(RegExp(r'^➤\s*'), '');
