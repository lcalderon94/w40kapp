import 'package:flutter/foundation.dart';
import 'package:warorgan_core/warorgan_core.dart';

/// Una lista que se está montando, y que avisa cuando cambia.
///
/// Envuelve al [Roster] del `core` en vez de duplicarlo: el precio, los presupuestos y la
/// legalidad ya los sabe él, y aquí solo se traduce «el jugador ha tocado algo» a «hay que volver
/// a pintar». Todo lo que cambia la lista pasa por aquí, así que no hay forma de mover una pieza
/// sin que se recalcule.
class ListaEnCurso extends ChangeNotifier {
  ListaEnCurso({required this.dataset, required Faction faccion, required BattleSize tamano})
      : roster = Roster(
          faction: faccion,
          pointsLimit: tamano.pointsLimit,
          name: 'Lista sin nombre',
        )..battleSize = tamano;

  final Dataset dataset;
  final Roster roster;

  Faction get faccion => roster.faction;
  BattleSize get tamano => roster.battleSize!;

  List<Detachment> get detachmentsDisponibles => dataset.detachmentsOf(faccion);

  void renombrar(String nombre) {
    roster.name = nombre;
    notifyListeners();
  }

  void elegirDetachment(Detachment detachment) {
    roster.detachments
      ..clear()
      ..add(detachment);
    notifyListeners();
  }

  void anadirUnidad(UnitEntry unidad) {
    roster.add(dataset.selectionFor(unidad));
    notifyListeners();
  }

  void quitarUnidad(Selection unidad) {
    roster.units.remove(unidad);
    notifyListeners();
  }

  /// Las opciones que se pueden elegir dentro de una selección, con lo ya elegido a la vista.
  List<Selection> opcionesDe(Selection seleccion) => dataset.optionsFor(seleccion);

  /// Cuántas de esa opción hay puestas ahora mismo.
  int cuantasHay(Selection padre, String entryId) => padre.children
      .where((hijo) => hijo.entryId == entryId)
      .fold(0, (total, hijo) => total + hijo.count);

  /// Pone una opción más. Si ya estaba, sube su cuenta en vez de duplicar la fila.
  void anadirOpcion(Selection padre, Selection opcion) {
    final puesta = padre.children.where((hijo) => hijo.entryId == opcion.entryId).firstOrNull;
    if (puesta != null) {
      puesta.count++;
    } else {
      padre.addChild(opcion);
    }
    notifyListeners();
  }

  /// Quita una. Al llegar a cero desaparece la fila, que dejarla a cero ensucia la ficha.
  void quitarOpcion(Selection padre, String entryId) {
    final puesta = padre.children.where((hijo) => hijo.entryId == entryId).firstOrNull;
    if (puesta == null) return;
    if (puesta.count > 1) {
      puesta.count--;
    } else {
      padre.children.remove(puesta);
    }
    notifyListeners();
  }

  int get puntos => roster.points;
  int get restantes => roster.pointsRemaining;

  /// Lo que gasta de un presupuesto del ejército: mejoras, Detachment Points.
  int gastoDe(String tipoDeCoste) =>
      roster.units.fold(0, (total, unidad) => total + unidad.costOf(tipoDeCoste));

  List<Violation> get incumplimientos => roster.validate();

  /// Los incumplimientos que salen de dentro de una unidad concreta.
  ///
  /// Casi todos lo son: 3.019 de las 6.149 unidades del dataset exigen elegir algo —un arma, un
  /// tamaño de escuadra— y nacen incumpliendo hasta que se elige. Poder señalar cuál es la que
  /// falla es lo que convierte «tu lista tiene 4 avisos» en algo accionable.
  List<Violation> incumplimientosDe(Selection unidad) {
    final suyas = unidad.descendantsAndSelf.toSet();
    return incumplimientos.where((v) => v.selection != null && suyas.contains(v.selection)).toList();
  }

  /// Restricciones que no se han podido comprobar, para poder decirlo en vez de callarlo.
  int get sinComprobar {
    roster.validate();
    return roster.uncheckedConstraints;
  }
}
