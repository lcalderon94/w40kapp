import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

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
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Text('$puntos pts',
                      style: const TextStyle(
                          color: Tema.acento, fontSize: 17, fontWeight: FontWeight.w700)),
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

/// La hoja de datos de una unidad, tal y como está impresa en el juego.
///
/// El orden es el de la hoja real, porque es el que el jugador ya tiene aprendido: la línea de
/// características, lo que sabe hacer y con qué pega. Va aquí y no en una pantalla porque hace
/// falta en dos sitios: al consultar una unidad del catálogo y al equipar una de la lista, donde
/// ver y editar tienen que estar juntos.
class HojaDeDatos extends StatelessWidget {
  const HojaDeDatos({
    super.key,
    required this.perfiles,
    required this.palabrasClave,
    this.encabezado,
  });

  final List<Profile> perfiles;
  final List<String> palabrasClave;

  /// Lo que va antes de la línea de características, si hace falta.
  final Widget? encabezado;

  @override
  Widget build(BuildContext context) {
    final porTipo = <String, List<Profile>>{};
    for (final perfil in perfiles) {
      porTipo.putIfAbsent(perfil.typeName, () => []).add(perfil);
    }
    final caracteristicas = porTipo.remove('Unit') ?? const <Profile>[];
    final habilidades = porTipo.remove('Abilities') ?? const <Profile>[];
    final aDistancia = porTipo.remove('Ranged Weapons') ?? const <Profile>[];
    final cuerpoACuerpo = porTipo.remove('Melee Weapons') ?? const <Profile>[];

    // La salvación invulnerable no es una característica más: el dataset la escribe con asterisco
    // —«5+*»— cuando solo vale contra unos ataques y deja la condición en una habilidad suelta.
    // Son 44 unidades con asterisco en la línea y otras 19 que ni siquiera la traen en ella.
    final invulnerable = Invulnerable.of(perfiles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (encabezado != null) encabezado!,
        for (final perfil in caracteristicas)
          _LineaDeCaracteristicas(perfil, invulnerable: invulnerable),
        if (habilidades.isNotEmpty) ...[
          const _Seccion('Habilidades'),
          for (final habilidad in habilidades) _Habilidad(habilidad),
        ],
        if (aDistancia.isNotEmpty) ...[
          const _Seccion('Armas a distancia'),
          _TablaDeArmas(aDistancia, columnaDeHabilidad: 'BS'),
        ],
        if (cuerpoACuerpo.isNotEmpty) ...[
          const _Seccion('Armas de cuerpo a cuerpo'),
          _TablaDeArmas(cuerpoACuerpo, columnaDeHabilidad: 'WS'),
        ],
        for (final entrada in porTipo.entries) ...[
          _Seccion(entrada.key),
          for (final perfil in entrada.value) _Habilidad(perfil),
        ],
        if (palabrasClave.isNotEmpty) ...[
          const _Seccion('Palabras clave'),
          _Palabras(palabrasClave),
        ],
      ],
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
    // El dataset la llama «InSv», que no la reconoce nadie. Y si la unidad la tiene solo en una
    // habilidad y no en la línea —19 en todo el dataset, entre ellas el Emperor's Champion—, se
    // pone igual: el jugador la necesita en el mismo sitio que las demás.
    final enLinea = valores.remove('InSv');
    final invSv = enLinea ?? invulnerable?.value;

    // Como en la hoja impresa: la etiqueta pequeña encima y el número grande dentro de su
    // recuadro. Es lo que se mira en mitad de una partida, así que se lee de lejos.
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
                if (invSv != null && invSv.trim().isNotEmpty && invSv.trim() != '-')
                  _Caja(
                      etiqueta: 'INV',
                      valor: invSv,
                      destacada: invulnerable?.isConditional ?? invSv.contains('*')),
              ],
            ),
          ),
        ),
        // Y la condición escrita, que es lo que el asterisco esconde: los Rangers la tienen solo
        // contra ataques a distancia y las Howling Banshees solo en cuerpo a cuerpo. Sin esto hay
        // que bajar a buscar la habilidad para saber si la salvación vale en este ataque o no.
        if (invulnerable != null && invulnerable!.isConditional)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                'Salvación invulnerable de ${invulnerable!.value} '
                'solo contra ${invulnerable!.scope}',
                style: const TextStyle(
                    color: Tema.acento, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.etiqueta, required this.valor, this.destacada = false});

  final String etiqueta;
  final String valor;

  /// Una salvación invulnerable que no vale contra todo se marca, para que no se lea como si sí.
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          Text(etiqueta.toUpperCase(),
              style: TextStyle(
                  color: destacada ? Tema.acento : Tema.textoTenue,
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
              border: Border.all(
                  color: destacada ? Tema.acento : Tema.superficieAlta, width: 1.5),
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

/// Las armas, con su línea de características. Se desplaza en horizontal si no cabe.
class _TablaDeArmas extends StatelessWidget {
  const _TablaDeArmas(this.armas, {required this.columnaDeHabilidad});

  final List<Profile> armas;
  final String columnaDeHabilidad;

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
                Text(_sinFlecha(arma.name),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                    padding: const EdgeInsets.only(top: 5),
                    child: TextoDeRegla(
                      arma.characteristics['Keywords']!,
                      estilo: const TextStyle(color: Tema.acento, fontSize: 12.5),
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
    // Barra llena de lado a lado, como los encabezados de la hoja impresa: separan de un vistazo
    // las armas de las habilidades sin tener que leer.
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
