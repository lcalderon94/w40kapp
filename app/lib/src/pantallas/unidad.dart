import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
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
            habilidades: Datos.de(context).abilitiesOf(unidad),
            palabrasClave: unidad.keywords,
            encabezado: BandaDeUnidad(
              nombre: unidad.name,
              rol: unidad.role,
              puntos: unidad.points,
            ),
          ),
        ],
      ),
    );
  }
}
