import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import '../widgets/hoja_de_datos.dart';

/// La ficha de una unidad del catálogo.
class PantallaDeUnidad extends StatelessWidget {
  const PantallaDeUnidad({super.key, required this.unidad, required this.faccion});

  final UnitEntry unidad;
  final Faction faccion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(unidad.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          HojaDeDatos(
            perfiles: Datos.de(context).sheetOf(unidad),
            palabrasClave: unidad.keywords,
            encabezado: _Encabezado(unidad: unidad),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.unidad});

  final UnitEntry unidad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (unidad.role != null)
            Text(unidad.role!.toUpperCase(),
                style: const TextStyle(
                    color: Tema.textoTenue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          const Spacer(),
          Text(
            unidad.points == null ? 'sin puntos' : '${unidad.points} pts',
            style: const TextStyle(
                color: Tema.acento, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// M, T, Sv, W, LD, OC: la línea que se consulta cada turno.
