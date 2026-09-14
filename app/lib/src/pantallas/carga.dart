import 'package:flutter/material.dart';

import '../tema.dart';

/// Lo primero que se ve, mientras se leen los datos.
///
/// Tarda: son 48 MB de reglas y más de cien mil nodos que hay que indexar antes de poder resolver
/// nada. Se hace una vez por arranque, y se prefiere decirlo a fingir que la app ya está lista.
class PantallaDeCarga extends StatelessWidget {
  const PantallaDeCarga({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: error != null ? _Error(error!) : const _Cargando(),
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('WarOrgan',
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: 6, color: Tema.acento)),
        SizedBox(height: 6),
        Text('Listas de Warhammer 40.000 en español',
            style: TextStyle(color: Tema.textoTenue, fontSize: 13, letterSpacing: 0.3)),
        SizedBox(height: 40),
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
              minHeight: 2, color: Tema.acento, backgroundColor: Tema.superficieAlta),
        ),
        SizedBox(height: 16),
        Text('Leyendo el reglamento…', style: TextStyle(color: Tema.textoTenue, fontSize: 12)),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Tema.aviso, size: 40),
        const SizedBox(height: 16),
        const Text('No se han podido cargar los datos',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text('$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Tema.textoTenue, fontSize: 13, height: 1.4)),
      ],
    );
  }
}
