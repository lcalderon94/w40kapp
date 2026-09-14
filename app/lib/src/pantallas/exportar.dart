import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';

/// La lista en texto plano, para copiarla y pegarla donde sea.
///
/// Se enseña antes de copiar en vez de copiar a ciegas: así se ve qué se va a mandar, y se puede
/// comprobar que los avisos van dentro —una lista ilegal tiene que salir diciéndolo, no colada—.
class PantallaDeExportar extends StatelessWidget {
  const PantallaDeExportar({super.key, required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    final texto = lista.comoTexto;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            tooltip: 'Copiar',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Lista copiada'),
                  backgroundColor: Tema.superficieAlta,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: SelectableText(
          texto,
          style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
