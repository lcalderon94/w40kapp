import 'package:flutter/material.dart';

import '../tema.dart';
import 'facciones.dart';
import 'wiki.dart';

/// Las dos patas de la app: construir listas y consultar el reglamento.
///
/// La Wiki no es un extra: la mitad de las veces que se abre una app de listas en mitad de una
/// partida es para mirar qué hace **[SUSTAINED HITS]**, y hasta ahora eso obligaba a salir a buscar
/// el reglamento por otro lado.
class PantallaDeInicio extends StatefulWidget {
  const PantallaDeInicio({super.key});

  @override
  State<PantallaDeInicio> createState() => _PantallaDeInicioState();
}

class _PantallaDeInicioState extends State<PantallaDeInicio> {
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: const [PantallaDeFacciones(), PantallaDeWiki()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        backgroundColor: Tema.superficie,
        indicatorColor: Tema.acento.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield, color: Tema.acento),
            label: 'Ejércitos',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: Tema.acento),
            label: 'Wiki',
          ),
        ],
      ),
    );
  }
}
