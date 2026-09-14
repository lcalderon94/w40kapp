import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import 'src/datos/repositorio.dart';
import 'src/pantallas/carga.dart';
import 'src/pantallas/inicio.dart';
import 'src/tema.dart';

void main() => runApp(const AplicacionWarOrgan());

/// WarOrgan-ES: constructor de listas de Warhammer 40.000 en español, sin conexión.
///
/// Los datos se cargan una sola vez aquí arriba, antes que nada: son 46 ficheros que se
/// referencian entre ellos y no sirve cargarlos a trozos según hagan falta.
class AplicacionWarOrgan extends StatefulWidget {
  const AplicacionWarOrgan({super.key});

  @override
  State<AplicacionWarOrgan> createState() => _AplicacionWarOrganState();
}

class _AplicacionWarOrganState extends State<AplicacionWarOrgan> {
  late final Future<Dataset> _datos = RepositorioDatos.cargar();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Dataset>(
      future: _datos,
      builder: (context, estado) {
        final app = MaterialApp(
          title: 'WarOrgan',
          debugShowCheckedModeBanner: false,
          theme: Tema.oscuro,
          home: estado.hasData
              ? const PantallaDeInicio()
              : PantallaDeCarga(error: estado.error),
        );
        return estado.hasData ? Datos(dataset: estado.data!, child: app) : app;
      },
    );
  }
}
