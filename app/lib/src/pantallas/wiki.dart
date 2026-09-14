import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../datos/repositorio.dart';
import '../tema.dart';
import '../widgets/texto_reglas.dart';

/// El glosario del reglamento básico, buscable y sin conexión.
///
/// Son las palabras clave que aparecen entre corchetes en las armas —[SUSTAINED HITS],
/// [DEVASTATING WOUNDS], [ANTI-INFANTRY 4+]— y que hay que ir a buscar al reglamento en mitad de
/// una partida. Estaban en el dataset desde el principio; lo único que faltaba era enseñarlas.
class PantallaDeWiki extends StatefulWidget {
  const PantallaDeWiki({super.key});

  @override
  State<PantallaDeWiki> createState() => _PantallaDeWikiState();
}

class _PantallaDeWikiState extends State<PantallaDeWiki> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final reglas = Datos.de(context).coreRules;
    final visibles = _busqueda.isEmpty
        ? reglas
        : reglas.where((r) {
            final buscado = _busqueda.toLowerCase();
            return r.name.toLowerCase().contains(buscado) ||
                r.description.toLowerCase().contains(buscado);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wiki'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (t) => setState(() => _busqueda = t),
              decoration: const InputDecoration(
                hintText: 'Buscar una regla',
                prefixIcon: Icon(Icons.search, color: Tema.textoTenue, size: 20),
              ),
            ),
          ),
        ),
      ),
      body: visibles.isEmpty
          ? const Center(
              child: Text('Ninguna regla con ese texto',
                  style: TextStyle(color: Tema.textoTenue)))
          : ListView.separated(
              itemCount: visibles.length,
              separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _Regla(visibles[i]),
            ),
    );
  }
}

class _Regla extends StatelessWidget {
  const _Regla(this.regla);

  final Rule regla;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(regla.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        iconColor: Tema.acento,
        collapsedIconColor: Tema.textoTenue,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [TextoDeRegla(regla.description)],
      ),
    );
  }
}
