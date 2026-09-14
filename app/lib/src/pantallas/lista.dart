import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import 'anadir_unidad.dart';
import 'elegir_detachment.dart';
import 'unidad_en_lista.dart';

/// La lista que se está montando.
///
/// Arriba, lo que se mira cada vez que se toca algo: cuántos puntos van, cuántos quedan y si la
/// lista es legal. Debajo, las unidades. El detachment va el primero porque es lo que decide qué
/// mejoras hay disponibles, así que elegirlo tarde obliga a rehacer.
class PantallaDeLista extends StatelessWidget {
  const PantallaDeLista({super.key, required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lista,
      builder: (context, _) {
        final incumplimientos = lista.incumplimientos;
        return Scaffold(
          appBar: AppBar(
            title: Text(lista.roster.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                tooltip: 'Renombrar',
                onPressed: () => _renombrar(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _Marcador(lista: lista, incumplimientos: incumplimientos),
              _Detachment(lista: lista),
              if (incumplimientos.isNotEmpty) _Incumplimientos(incumplimientos),
              _Unidades(lista: lista),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Tema.acento,
            foregroundColor: Tema.fondo,
            icon: const Icon(Icons.add),
            label: const Text('Añadir unidad'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PantallaDeAnadirUnidad(lista: lista),
            )),
          ),
        );
      },
    );
  }

  Future<void> _renombrar(BuildContext context) async {
    final control = TextEditingController(text: lista.roster.name);
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tema.superficie,
        title: const Text('Nombre de la lista'),
        content: TextField(controller: control, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, control.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (nombre != null && nombre.trim().isNotEmpty) lista.renombrar(nombre.trim());
  }
}

/// Puntos, presupuestos y legalidad: lo que se consulta cada vez que se toca algo.
class _Marcador extends StatelessWidget {
  const _Marcador({required this.lista, required this.incumplimientos});

  final ListaEnCurso lista;
  final List<Violation> incumplimientos;

  @override
  Widget build(BuildContext context) {
    final puntos = lista.puntos;
    final limite = lista.roster.pointsLimit;
    final pasado = puntos > limite;
    final mejoras = lista.gastoDe(enhancementsCostTypeId);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$puntos',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w300,
                      color: pasado ? Tema.aviso : Tema.texto)),
              Text(' / $limite pts',
                  style: const TextStyle(fontSize: 15, color: Tema.textoTenue)),
              const Spacer(),
              _Sello(
                legal: incumplimientos.isEmpty,
                texto: incumplimientos.isEmpty
                    ? 'Legal'
                    : '${incumplimientos.length} ${incumplimientos.length == 1 ? "aviso" : "avisos"}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: limite == 0 ? 0 : (puntos / limite).clamp(0.0, 1.0),
              minHeight: 5,
              color: pasado ? Tema.aviso : Tema.acento,
              backgroundColor: Tema.superficieAlta,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Dato(etiqueta: 'Tamaño', valor: _tamanoCorto(lista.tamano.name)),
              _Dato(etiqueta: 'Mejoras', valor: '$mejoras'),
              _Dato(etiqueta: 'Unidades', valor: '${lista.roster.units.length}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sello extends StatelessWidget {
  const _Sello({required this.legal, required this.texto});

  final bool legal;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final color = legal ? Tema.acento : Tema.aviso;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texto,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta.toUpperCase(),
              style: const TextStyle(
                  color: Tema.textoTenue,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Detachment extends StatelessWidget {
  const _Detachment({required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    final elegido = lista.roster.detachment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PantallaDeElegirDetachment(lista: lista),
        )),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Tema.superficie,
            borderRadius: BorderRadius.circular(10),
            border: elegido == null
                ? Border.all(color: Tema.aviso.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DETACHMENT',
                        style: TextStyle(
                            color: Tema.textoTenue,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 3),
                    Text(elegido?.name ?? 'Sin elegir',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: elegido == null ? Tema.aviso : Tema.texto)),
                    if (elegido?.ruleName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(elegido!.ruleName!,
                            style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Tema.textoTenue, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Incumplimientos extends StatelessWidget {
  const _Incumplimientos(this.incumplimientos);

  final List<Violation> incumplimientos;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Tema.aviso.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final incumplimiento in incumplimientos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.priority_high, color: Tema.aviso, size: 14),
                  ),
                  Expanded(
                    child: Text('$incumplimiento',
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Unidades extends StatelessWidget {
  const _Unidades({required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    if (lista.roster.units.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 56, horizontal: 32),
        child: Text(
          'La lista está vacía.\nElige un detachment y empieza a añadir unidades.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Tema.textoTenue, height: 1.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 6),
          child: Text('UNIDADES',
              style: TextStyle(
                  color: Tema.acento,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4)),
        ),
        for (final unidad in lista.roster.units) _Unidad(lista: lista, unidad: unidad),
      ],
    );
  }
}

class _Unidad extends StatelessWidget {
  const _Unidad({required this.lista, required this.unidad});

  final ListaEnCurso lista;
  final Selection unidad;

  @override
  Widget build(BuildContext context) {
    final equipo = unidad.children.where((h) => h.name.isNotEmpty).toList();
    final avisos = lista.incumplimientosDe(unidad);
    return Dismissible(
      key: ObjectKey(unidad),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Tema.aviso.withValues(alpha: 0.22),
        child: const Icon(Icons.delete_outline, color: Tema.aviso),
      ),
      onDismissed: (_) => lista.quitarUnidad(unidad),
      child: ListTile(
        title: Text(unidad.name, style: const TextStyle(fontSize: 15)),
        subtitle: equipo.isEmpty
            ? null
            : Text(
                equipo.map((h) => '${h.count}× ${h.name}').join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tema.textoTenue, fontSize: 12, height: 1.3),
              ),
        leading: avisos.isEmpty
            ? null
            : Tooltip(
                message: avisos.map((v) => v.message).join('\n'),
                child: const Icon(Icons.error_outline, color: Tema.aviso, size: 18),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unidad.unresolvedCostModifiers > 0)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: 'El precio puede quedarse corto: hay un modifier que no se sabe evaluar',
                  child: Icon(Icons.help_outline, color: Tema.textoTenue, size: 16),
                ),
              ),
            Text('${unidad.points} pts',
                style: const TextStyle(
                    color: Tema.acento, fontSize: 13, fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right, color: Tema.textoTenue, size: 20),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PantallaDeUnidadEnLista(lista: lista, unidad: unidad),
        )),
      ),
    );
  }
}

/// «1. Incursion (1000 Point limit)» se queda en «Incursion».
String _tamanoCorto(String nombre) {
  final sinNumero = nombre.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  final parentesis = sinNumero.indexOf(' (');
  return parentesis == -1 ? sinNumero : sinNumero.substring(0, parentesis);
}
