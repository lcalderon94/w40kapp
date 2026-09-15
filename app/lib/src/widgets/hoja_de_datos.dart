import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../tema.dart';
import 'texto_reglas.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (encabezado != null) encabezado!,
        for (final perfil in caracteristicas) _LineaDeCaracteristicas(perfil),
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
  const _LineaDeCaracteristicas(this.perfil);

  final Profile perfil;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final caracteristica in perfil.characteristics.entries)
            Column(
              children: [
                Text(caracteristica.key,
                    style: const TextStyle(
                        color: Tema.textoTenue,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 3),
                Text(caracteristica.value,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
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
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          TextoDeRegla(texto),
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
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
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
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          Text(nombre,
              style: const TextStyle(
                  color: Tema.textoTenue, fontSize: 9.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(titulo.toUpperCase(),
          style: const TextStyle(
              color: Tema.acento,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4)),
    );
  }
}

/// El dataset marca los subperfiles de un arma con «➤». En la ficha sobra.
String _sinFlecha(String nombre) => nombre.replaceFirst(RegExp(r'^➤\s*'), '');
