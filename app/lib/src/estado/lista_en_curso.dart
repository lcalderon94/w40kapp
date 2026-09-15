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
      : perdidas = const [],
        roster = Roster(
          faction: faccion,
          pointsLimit: tamano.pointsLimit,
          name: 'Lista sin nombre',
        )..battleSize = tamano;

  /// Una lista ya montada, recuperada de lo guardado.
  ListaEnCurso.montada({required this.dataset, required this.roster, this.perdidas = const []});

  final Dataset dataset;
  final Roster roster;

  /// Lo que estaba guardado y hoy ya no se puede montar. Se enseña una vez, al abrirla.
  final List<String> perdidas;

  Faction get faccion => roster.faction;
  BattleSize get tamano => roster.battleSize!;

  List<Detachment> get detachmentsDisponibles => dataset.detachmentsOf(faccion);

  /// Las unidades que esta lista puede llevar de verdad.
  ///
  /// No son todas las del catálogo: el dataset esconde las Legends, los aliados y las que piden un
  /// detachment concreto —los demonios de Nurgle solo entran con Tallyband Summoners—, y ofrecerlas
  /// igualmente sería dar por buena una lista ilegal.
  List<UnitEntry> get unidadesDisponibles => roster.availableUnits;

  /// Los interruptores de contenido que ofrece esta facción, y cuáles están encendidos.
  List<Rule> get interruptores => dataset.visibilityOptionsOf(faccion);

  bool estaEncendido(String id) => roster.shownOptions.contains(id);

  void cambiarInterruptor(String id, bool encendido) {
    if (encendido) {
      roster.shownOptions.add(id);
    } else {
      roster.shownOptions.remove(id);
      // Lo que ya estaba puesto se queda: quitar unidades de la lista sin avisar sería peor que
      // dejar una visible de más, y la validación sigue siendo la que manda.
    }
    notifyListeners();
  }

  void renombrar(String nombre) {
    roster.name = nombre;
    notifyListeners();
  }

  /// Deja un único detachment puesto. Se usa al elegir el primero.
  void elegirDetachment(Detachment detachment) {
    roster.detachments
      ..clear()
      ..add(detachment);
    notifyListeners();
  }

  /// Pone o quita un detachment.
  ///
  /// En 11ª un ejército puede llevar más de uno: lo que los limita no es un «elige uno» sino el
  /// presupuesto de Detachment Points, que a 2000 puntos son tres. Tallyband Summoners cuesta dos,
  /// así que queda uno por gastar y hay que poder gastarlo.
  void alternarDetachment(Detachment detachment) {
    final puesto = roster.detachments.where((d) => d.id == detachment.id).firstOrNull;
    if (puesto != null) {
      roster.detachments.remove(puesto);
    } else {
      roster.detachments.add(detachment);
    }
    notifyListeners();
  }

  bool tieneDetachment(Detachment detachment) =>
      roster.detachments.any((d) => d.id == detachment.id);

  /// Cuántos Detachment Points gasta la lista y cuántos permite el tamaño de partida.
  ({int gastados, int? presupuesto}) get puntosDeDetachment {
    final gastados = roster.detachments
        .fold<int>(0, (t, d) => t + d.detachmentPoints);
    return (gastados: gastados, presupuesto: roster.detachmentPointsBudget);
  }

  /// Si añadir ese detachment cabe en el presupuesto.
  bool cabeDetachment(Detachment detachment) {
    if (tieneDetachment(detachment)) return true;
    final uso = puntosDeDetachment;
    if (uso.presupuesto == null) return true;
    return uso.gastados + detachment.detachmentPoints <= uso.presupuesto!;
  }

  void anadirUnidad(UnitEntry unidad) {
    // Del roster, no del dataset: así la unidad entra sin el equipo que solo existe con otro
    // detachment, que si no se cuela y además le cambia las palabras clave.
    roster.add(roster.selectionFor(unidad));
    notifyListeners();
  }

  void quitarUnidad(Selection unidad) {
    roster.remove(unidad);
    notifyListeners();
  }

  /// Las opciones que esta unidad puede elegir de verdad.
  ///
  /// El dataset comparte listas de armas entre varias unidades y enseña en cada una solo las
  /// suyas; ofrecerlas todas pone en la ficha de una unidad el equipo de otra.
  List<Selection> opcionesDe(Selection seleccion) => roster.optionsFor(seleccion);

  /// Cuántas de esa opción hay puestas ahora mismo.
  int cuantasHay(Selection padre, String entryId) => padre.children
      .where((hijo) => hijo.entryId == entryId)
      .fold(0, (total, hijo) => total + hijo.count);

  /// Pone una opción más. Si ya estaba, sube su cuenta en vez de duplicar la fila.
  ///
  /// Cuando el grupo del que sale solo deja elegir una cosa, lo nuevo **sustituye** a lo viejo.
  /// Apilarlo dejaba la unidad incumpliendo para siempre: el Campeón de la Plaga nace con sus
  /// Plague knives puestas y elegir el Power fist encima ponía dos armas en un grupo de una.
  void anadirOpcion(Selection padre, Selection opcion) {
    if (opcion.groupId != null && _soloUna(padre, opcion.groupId!)) {
      padre.children.removeWhere((hijo) => hijo.groupId == opcion.groupId);
    }
    final puesta = padre.children.where((hijo) => hijo.entryId == opcion.entryId).firstOrNull;
    if (puesta != null) {
      puesta.count++;
    } else {
      padre.addChild(opcion);
    }
    notifyListeners();
  }

  /// Pone la opción si no está y la quita si ya está.
  ///
  /// Es lo que se espera de una casilla: se pulsa para marcar y se vuelve a pulsar para
  /// desmarcar. Solo añadir deja atrapado al jugador, que no puede deshacer una mejora ni volver a
  /// dejar un grupo vacío cuando el dataset lo permite.
  void alternarOpcion(Selection padre, Selection opcion) {
    final puesta = padre.children.where((h) => h.entryId == opcion.entryId).firstOrNull;
    if (puesta != null) {
      padre.children.remove(puesta);
      notifyListeners();
      return;
    }
    anadirOpcion(padre, opcion);
  }

  /// El catálogo agrupado por rol de batalla, en el orden de la hoja de ejército.
  ///
  /// Con [soloLasQueCaben] se dejan fuera las que no entran en los puntos que quedan, que es lo
  /// que evita perder el tiempo mirando lo que no te puedes permitir.
  List<({String rol, List<UnitEntry> unidades})> catalogoPorRol({
    String busqueda = '',
    bool soloLasQueCaben = false,
  }) {
    final texto = _sinTildes(busqueda);
    var todas = unidadesDisponibles;
    if (texto.isNotEmpty) {
      todas = todas.where((u) => _sinTildes(u.name).contains(texto)).toList();
    }
    if (soloLasQueCaben) {
      todas = todas.where((u) => (u.points ?? 0) <= restantes).toList();
    }
    todas.sort((a, b) => a.name.compareTo(b.name));

    final salida = <({String rol, List<UnitEntry> unidades})>[];
    final puestas = <String>{};
    for (final rol in dataset.standardForce.roles) {
      final suyas = todas
          .where((u) => !puestas.contains(u.id) && u.role == rol.name)
          .toList();
      if (suyas.isEmpty) continue;
      puestas.addAll(suyas.map((u) => u.id));
      salida.add((rol: rol.name, unidades: suyas));
    }
    final resto = todas.where((u) => !puestas.contains(u.id)).toList();
    if (resto.isNotEmpty) salida.add((rol: 'Otras', unidades: resto));
    return salida;
  }

  static String _sinTildes(String x) {
    const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    return x.toLowerCase().split('').map((c) => tildes[c] ?? c).join();
  }

  /// Las unidades de la lista agrupadas por rol de batalla, en el orden de la hoja de ejército.
  ///
  /// Los líderes unidos a otra unidad no salen por su cuenta: van anidados bajo ella, que es como
  /// se juegan. El orden lo declara la propia fuerza, no está escrito a mano aquí.
  List<({String rol, List<Selection> unidades})> get unidadesPorRol {
    final sueltas = roster.units.where((u) => u.attachedTo == null).toList();
    final salida = <({String rol, List<Selection> unidades})>[];
    final puestas = <Selection>{};
    for (final rol in dataset.standardForce.roles) {
      final suyas = sueltas
          .where((u) => !puestas.contains(u) && u.primaryCategoryId == rol.id)
          .toList();
      if (suyas.isEmpty) continue;
      puestas.addAll(suyas);
      salida.add((rol: rol.name, unidades: suyas));
    }
    final resto = sueltas.where((u) => !puestas.contains(u)).toList();
    if (resto.isNotEmpty) salida.add((rol: 'Otras', unidades: resto));
    return salida;
  }

  /// Los líderes unidos a una unidad.
  List<Selection> lideresDe(Selection unidad) => roster.leadersOn(unidad).toList();

  /// A qué unidades de la lista se puede unir este líder ahora mismo.
  List<Selection> anfitrionesDe(Selection lider) => roster.hostsFor(lider);

  void unir(Selection lider, Selection? anfitrion) {
    roster.attach(lider, anfitrion);
    notifyListeners();
  }

  /// La entrada de catálogo de una selección, para poder pintar su hoja de datos.
  UnitEntry? entradaDe(Selection seleccion) =>
      faccion.units.where((u) => u.id == seleccion.entryId).firstOrNull;

  /// Si de ese grupo solo cabe una cosa, que es lo que lo convierte en un botón de radio.
  bool _soloUna(Selection padre, String groupId) {
    final grupo = padre.groups.where((g) => g.id == groupId).firstOrNull;
    if (grupo == null) return false;
    return roster.groupUsage(padre, grupo).maximo == 1;
  }

  /// Si cabe una más: lo mira el motor, que es quien conoce los techos del dataset.
  bool cabeOtra(Selection padre, Selection opcion) => roster.canAdd(padre, opcion);

  /// Cuántas cabe elegir de un grupo y cuántas hay, con los modifiers ya aplicados.
  ({int puestas, int? minimo, int? maximo}) usoDeGrupo(Selection padre, OptionGroup grupo) =>
      roster.groupUsage(padre, grupo);

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

  /// La lista en texto plano, para pegarla donde sea.
  String get comoTexto => Exportar.aTexto(roster);

  /// Lo que hay que guardar para poder volver a montarla.
  String get paraGuardar => Guardado.aTexto(roster);

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
