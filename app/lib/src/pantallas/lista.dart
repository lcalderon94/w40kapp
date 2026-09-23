import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import 'facciones.dart';
import 'anadir_unidad.dart';
import 'elegir_detachment.dart';
import 'exportar.dart';
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
        // El color del ejército por toda la pantalla: la Death Guard es verde podrido y los Blood
        // Angels rojos, y el jugador lo reconoce sin leer. Un único acento para las 36 hacía que
        // todas las listas se vieran igual.
        return ColorDeEjercito(
          color: colorDeFaccion(corto(lista.faccion.name)),
          // Builder para que lo de dentro vea el color: un InheritedWidget solo lo ven sus
          // descendientes, y sin esto el mismo `build` seguiría leyendo el acento de la app.
          child: Builder(builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(lista.roster.name),
            actions: [
              // El interruptor entre montar la lista y mirarla. En la mesa se mira, y ahí un
              // toque de más en un contador estropea lo que costó montar.
              _BotonDeModo(lista: lista),
              if (lista.modoEdicion) ...[
                // Deshacer y rehacer: quitar una unidad por error y tener que rehacerla a mano es
                // lo que hace que montar una lista canse.
                IconButton(
                  icon: const Icon(Icons.undo, size: 20),
                  tooltip: 'Deshacer',
                  onPressed: lista.sePuedeDeshacer ? lista.deshacer : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 20),
                  tooltip: 'Rehacer',
                  onPressed: lista.sePuedeRehacer ? lista.rehacer : null,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.ios_share, size: 20),
                tooltip: 'Exportar',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PantallaDeExportar(lista: lista),
                )),
              ),
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
          floatingActionButton: !lista.modoEdicion
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: ColorDeEjercito.de(context),
                  foregroundColor: Tema.fondo,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir unidad'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PantallaDeAnadirUnidad(lista: lista),
                  )),
                ),
          )),
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

/// El interruptor entre montar la lista y mirarla.
///
/// En WarOrgan son dos pantallas distintas y por algo: montando hacen falta contadores, botones y
/// avisos; en la mesa lo que hace falta es leer lo que llevas, y cualquiera de esos botones es un
/// toque que estropea la lista sin querer.
class _BotonDeModo extends StatelessWidget {
  const _BotonDeModo({required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final editando = lista.modoEdicion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Material(
        color: editando ? acento : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: const ValueKey('boton-modo'),
          borderRadius: BorderRadius.circular(5),
          onTap: lista.alternarModo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: acento.withValues(alpha: 0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(editando ? Icons.edit : Icons.visibility,
                    size: 16, color: editando ? Tema.fondo : acento),
                const SizedBox(width: 6),
                Text(editando ? 'Editando' : 'Viendo',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: editando ? Tema.fondo : acento)),
              ],
            ),
          ),
        ),
      ),
    );
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
              color: pasado ? Tema.aviso : ColorDeEjercito.de(context),
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
    final color = legal ? ColorDeEjercito.de(context) : Tema.aviso;
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
                    // La disposición de fuerza, que es lo que decide qué misiones juega el ejército.
                    if (elegido != null && elegido.disposiciones.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(elegido.disposiciones.join(' · '),
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

    // Por rol de batalla y en el orden de la hoja de ejército, que es como se lee una lista.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final grupo in lista.unidadesPorRol) ...[
          _Rol(grupo.rol, grupo.unidades.length),
          for (final unidad in grupo.unidades)
            _Unidad(lista: lista, unidad: unidad),
        ],
      ],
    );
  }
}

class _Rol extends StatelessWidget {
  const _Rol(this.nombre, this.cuantas);

  final String nombre;
  final int cuantas;

  @override
  Widget build(BuildContext context) {
    final acento = ColorDeEjercito.de(context);
    final sobre =
        acento.computeLuminance() > 0.45 ? const Color(0xFF14120F) : Colors.white;
    return Container(
      color: acento.withValues(alpha: 0.85),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      margin: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(nombre.toUpperCase(),
                style: TextStyle(
                    color: sobre,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3)),
          ),
          Text('$cuantas',
              style: TextStyle(color: sobre.withValues(alpha: 0.8), fontSize: 12)),
        ],
      ),
    );
  }
}

class _Unidad extends StatelessWidget {
  const _Unidad({required this.lista, required this.unidad, this.unida = false});

  final ListaEnCurso lista;
  final Selection unidad;

  /// Si va anidada bajo la unidad a la que se ha unido.
  final bool unida;

  @override
  Widget build(BuildContext context) {
    final equipo = unidad.children.where((h) => h.name.isNotEmpty).toList();
    final avisos = lista.incumplimientosDe(unidad);
    final lideres = unida ? const <Selection>[] : lista.lideresDe(unidad);
    final puedeUnirse = !unida && lista.anfitrionesDe(unidad).isNotEmpty;

    final editando = lista.modoEdicion;
    final tarjeta = ListTile(
        contentPadding: EdgeInsets.only(left: unida ? 34 : 16, right: 8),
        title: Row(
          children: [
            if (unida)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 15, color: Tema.textoTenue),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(unidad.displayName, style: const TextStyle(fontSize: 15)),
                  if (unidad.customName != null)
                    Text(unidad.name,
                        style: const TextStyle(color: Tema.textoTenue, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
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
            if (editando)
              IconButton(
                tooltip: 'Ponerle nombre',
                icon: const Icon(Icons.drive_file_rename_outline,
                    size: 18, color: Tema.textoTenue),
                onPressed: () => _renombrarUnidad(context),
              ),
            if (editando)
              IconButton(
                key: const ValueKey('quitar-de-la-lista'),
                tooltip: 'Quitar de la lista',
                icon: const Icon(Icons.delete_outline, size: 18, color: Tema.textoTenue),
                onPressed: () => lista.quitarUnidad(unidad),
              ),
            if (editando && puedeUnirse)
              IconButton(
                tooltip: 'Unir a una unidad',
                icon: const Icon(Icons.link, size: 19, color: Tema.textoTenue),
                onPressed: () => _elegirAnfitrion(context),
              ),
            if (editando && unida)
              IconButton(
                tooltip: 'Separar',
                icon: const Icon(Icons.link_off, size: 19, color: Tema.textoTenue),
                onPressed: () => lista.unir(unidad, null),
              ),
            Text('${unidad.points} pts',
                style: const TextStyle(
                    color: Tema.acento, fontSize: 13, fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right, color: Tema.textoTenue, size: 20),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          // Viendo, la unidad se abre como hoja de datos: lo que le has puesto, y nada que tocar.
          builder: (_) => editando
              ? PantallaDeUnidadEnLista(lista: lista, unidad: unidad)
              : PantallaDeUnidadEnVisor(lista: lista, unidad: unidad),
        )),
    );

    final fila = !editando
        ? tarjeta
        : Dismissible(
            key: ObjectKey(unidad),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              color: Tema.aviso.withValues(alpha: 0.22),
              child: const Icon(Icons.delete_outline, color: Tema.aviso),
            ),
            onDismissed: (_) => lista.quitarUnidad(unidad),
            child: tarjeta,
          );

    if (lideres.isEmpty) return fila;
    // El líder va debajo de su unidad y sangrado: se juegan como una sola cosa.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fila,
        for (final lider in lideres)
          _Unidad(lista: lista, unidad: lider, unida: true),
      ],
    );
  }

  Future<void> _renombrarUnidad(BuildContext context) async {
    final control = TextEditingController(text: unidad.customName ?? '');
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tema.superficie,
        title: Text(unidad.name),
        content: TextField(
          controller: control,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'La Guardia Podrida'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(control.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (nuevo != null) lista.renombrarUnidad(unidad, nuevo);
  }

  Future<void> _elegirAnfitrion(BuildContext context) async {
    final candidatos = lista.anfitrionesDe(unidad);
    final elegido = await showModalBottomSheet<Selection>(
      context: context,
      backgroundColor: Tema.superficie,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Unir ${unidad.name} a',
                  style: const TextStyle(
                      color: Tema.acento, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            // Todas las que admite, y las que ahora no caben deshabilitadas con el motivo.
            for (final c in candidatos)
              Builder(builder: (context) {
                final motivo = lista.motivoParaUnir(unidad, c);
                return ListTile(
                  title: Text(c.displayName),
                  subtitle: motivo == null
                      ? null
                      : Text(motivo, style: const TextStyle(color: Tema.aviso, fontSize: 12)),
                  enabled: motivo == null,
                  onTap: motivo == null ? () => Navigator.of(context).pop(c) : null,
                );
              }),
          ],
        ),
      ),
    );
    if (elegido != null) lista.unir(unidad, elegido);
  }
}

/// «1. Incursion (1000 Point limit)» se queda en «Incursion».
String _tamanoCorto(String nombre) {
  final sinNumero = nombre.replaceFirst(RegExp(r'^\d+\.\s*'), '');
  final parentesis = sinNumero.indexOf(' (');
  return parentesis == -1 ? sinNumero : sinNumero.substring(0, parentesis);
}
