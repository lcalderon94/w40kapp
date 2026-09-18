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
  Roster roster;

  /// Las instantáneas de antes de cada cambio, y las que se deshicieron.
  ///
  /// Se guarda el mismo JSON que usa [Guardado], así que deshacer es volver a montar la lista con
  /// lo que había: no hay una segunda forma de representarla que pueda quedarse desincronizada.
  final List<Map<String, dynamic>> _antes = [];
  final List<Map<String, dynamic>> _despues = [];

  bool get sePuedeDeshacer => _antes.isNotEmpty;
  bool get sePuedeRehacer => _despues.isNotEmpty;

  /// Apunta el estado actual antes de cambiarlo.
  void _apunta() {
    _antes.add(Guardado.aJson(roster));
    if (_antes.length > 50) _antes.removeAt(0);
    _despues.clear();
  }

  void _restaurar(Map<String, dynamic> instantanea) {
    roster = Guardado.deJson(dataset, instantanea).roster;
    notifyListeners();
  }

  void deshacer() {
    if (_antes.isEmpty) return;
    _despues.add(Guardado.aJson(roster));
    _restaurar(_antes.removeLast());
  }

  void rehacer() {
    if (_despues.isEmpty) return;
    _antes.add(Guardado.aJson(roster));
    _restaurar(_despues.removeLast());
  }

  /// Le pone nombre propio a una unidad de la lista.
  void renombrarUnidad(Selection unidad, String nombre) {
    _apunta();
    unidad.customName = nombre.trim().isEmpty ? null : nombre.trim();
    notifyListeners();
  }

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
    _apunta();
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
    _apunta();
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
    _apunta();
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
    _apunta();
    // Del roster, no del dataset: así la unidad entra sin el equipo que solo existe con otro
    // detachment, que si no se cuela y además le cambia las palabras clave.
    roster.add(roster.selectionFor(unidad));
    notifyListeners();
  }

  void quitarUnidad(Selection unidad) {
    _apunta();
    roster.remove(unidad);
    notifyListeners();
  }

  /// Las opciones que esta unidad puede elegir de verdad.
  ///
  /// El dataset comparte listas de armas entre varias unidades y enseña en cada una solo las
  /// suyas; ofrecerlas todas pone en la ficha de una unidad el equipo de otra.
  List<Selection> opcionesDe(Selection seleccion) => roster.optionsFor(seleccion);

  /// Cuántas de esa opción hay puestas ahora mismo, **en su grupo**.
  ///
  /// La misma arma sale en dos grupos de la misma unidad —el Electroscourge del Defiler sustituye
  /// al lanzamisiles o al baleflamer, y es la misma entrada—, así que contarla por entrada a secas
  /// marcaba las dos casillas de una sola pulsación. Pasa en 295 unidades del dataset.
  int cuantasHay(Selection padre, Selection opcion) => padre.cuantasDe(opcion);

  /// Pone una opción más. Si ya estaba, sube su cuenta en vez de duplicar la fila.
  ///
  /// Cuando el grupo del que sale solo deja elegir una cosa, lo nuevo **sustituye** a lo viejo.
  /// Apilarlo dejaba la unidad incumpliendo para siempre: el Campeón de la Plaga nace con sus
  /// Plague knives puestas y elegir el Power fist encima ponía dos armas en un grupo de una.
  void anadirOpcion(Selection padre, Selection opcion) {
    _apunta();
    if (opcion.groupId != null && _soloUna(padre, opcion.groupId!)) {
      padre.children.removeWhere((hijo) => hijo.groupId == opcion.groupId);
    }
    final puesta = padre.puestaDe(opcion);
    if (puesta != null) {
      puesta.count++;
    } else {
      padre.addChild(opcion);
      // Lo que entra llega con lo suyo puesto: hay opciones que a su vez preguntan algo, y sin
      // rellenarlas la unidad se queda ilegal por un hueco que el jugador no ha abierto.
      roster.completeMinimums(opcion);
    }
    notifyListeners();
  }

  /// Elige esta opción dentro de un grupo que solo admite una: la pone y quita la que hubiera.
  ///
  /// No alterna. Un grupo de «elige exactamente un arma principal» no se puede dejar vacío, y
  /// dejar que se desmarque era lo que ponía «el baleflamer es obligatorio» en el Defiler: se
  /// quitaba el arma que el dataset exige y salía el aviso de un hueco que el jugador no sabía
  /// que había abierto. Un arma no es obligatoria; elegir una de las cuatro, sí.
  void elegirOpcion(Selection padre, Selection opcion) {
    if (padre.puestaDe(opcion) != null) return;
    anadirOpcion(padre, opcion);
  }

  /// Pone la opción si no está y la quita si ya está.
  ///
  /// Es lo que se espera de una casilla: se pulsa para marcar y se vuelve a pulsar para
  /// desmarcar. Solo añadir deja atrapado al jugador, que no puede deshacer una mejora ni volver a
  /// dejar un grupo vacío cuando el dataset lo permite.
  void alternarOpcion(Selection padre, Selection opcion) {
    final puesta = padre.puestaDe(opcion);
    if (puesta != null) {
      _apunta();
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

    // Los aliados van aparte y al final. Los Chaos Knights no son de la Death Guard, ni los
    // inquisidores de Agents of the Imperium son de nadie: mezclarlos en Personajes y Vehículos
    // junto a los propios es meter dos cosas distintas en el mismo cajón. Quien lo dice es el
    // dataset, que a cada uno le pone su categoría «Allies: …» cuando la lista no es la suya.
    final propias = <UnitEntry>[];
    final aliadas = <String, List<UnitEntry>>{};
    for (final u in todas) {
      final aliado = roster.allyOf(u);
      if (aliado == null) {
        propias.add(u);
      } else {
        aliadas.putIfAbsent(aliado, () => []).add(u);
      }
    }

    final salida = <({String rol, List<UnitEntry> unidades})>[];
    final puestas = <String>{};
    for (final rol in dataset.standardForce.roles) {
      final suyas = propias
          .where((u) => !puestas.contains(u.id) && u.role == rol.name)
          .toList();
      if (suyas.isEmpty) continue;
      puestas.addAll(suyas.map((u) => u.id));
      salida.add((rol: rol.name, unidades: suyas));
    }
    final resto = propias.where((u) => !puestas.contains(u.id)).toList();
    if (resto.isNotEmpty) salida.add((rol: 'Otras', unidades: resto));

    final nombres = aliadas.keys.toList()..sort();
    for (final nombre in nombres) {
      salida.add((rol: 'Aliados · $nombre', unidades: aliadas[nombre]!));
    }
    return salida;
  }

  /// De qué facción aliada es una unidad, o `null` si es de la propia.
  String? aliadoDe(UnitEntry unidad) => roster.allyOf(unidad);

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

    // Como en el catálogo: los aliados en su propia sección, no repartidos entre los roles de la
    // facción. Una lista de Death Guard con dos War Dogs tiene que enseñarlos como lo que son.
    final propias = <Selection>[];
    final aliadas = <String, List<Selection>>{};
    for (final u in sueltas) {
      final entrada = entradaDe(u);
      final aliado = entrada == null ? null : roster.allyOf(entrada);
      if (aliado == null) {
        propias.add(u);
      } else {
        aliadas.putIfAbsent(aliado, () => []).add(u);
      }
    }

    final salida = <({String rol, List<Selection> unidades})>[];
    final puestas = <Selection>{};
    for (final rol in dataset.standardForce.roles) {
      final suyas = propias
          .where((u) => !puestas.contains(u) && u.primaryCategoryId == rol.id)
          .toList();
      if (suyas.isEmpty) continue;
      puestas.addAll(suyas);
      salida.add((rol: rol.name, unidades: suyas));
    }
    final resto = propias.where((u) => !puestas.contains(u)).toList();
    if (resto.isNotEmpty) salida.add((rol: 'Otras', unidades: resto));

    final nombres = aliadas.keys.toList()..sort();
    for (final nombre in nombres) {
      salida.add((rol: 'Aliados · $nombre', unidades: aliadas[nombre]!));
    }
    return salida;
  }

  /// Los líderes unidos a una unidad.
  List<Selection> lideresDe(Selection unidad) => roster.leadersOn(unidad).toList();

  /// A qué unidades de la lista se puede unir este líder ahora mismo.
  List<Selection> anfitrionesDe(Selection lider) => roster.hostsFor(lider);

  void unir(Selection lider, Selection? anfitrion) {
    _apunta();
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

  /// Si se puede quitar una: el dataset marca el equipo fijo con un mínimo en la propia opción.
  bool sePuedeQuitar(Selection padre, Selection opcion, {bool hayAlternativas = false}) =>
      roster.canRemove(padre, opcion, hayAlternativas: hayAlternativas);

  /// Si esa opción es equipo de serie que no se elige, y por tanto no lleva contador.
  bool esFija(Selection padre, Selection opcion, {bool hayAlternativas = false}) =>
      roster.isFixed(padre, opcion, hayAlternativas: hayAlternativas);

  /// Lo que la hoja impresa dice que se puede cambiar en esta unidad.
  ///
  /// Es texto, no regla: los topes y el precio siguen saliendo del dataset. Está para saber qué se
  /// está eligiendo —«por cada 5 miniaturas, 1 puede cambiar el bólter»—, que es justo lo que los
  /// números solos no dicen.
  List<String> notasDeEquipoDe(Selection unidad) {
    final entrada = entradaDe(unidad);
    return entrada == null ? const [] : dataset.wargearNotesOf(entrada);
  }

  /// Las habilidades de reglamento —CORE y FACTION— de una unidad de la lista.
  List<Ability> habilidadesDe(Selection unidad) {
    final entrada = entradaDe(unidad);
    return entrada == null ? const [] : dataset.abilitiesOf(entrada);
  }

  /// Cuántas miniaturas llevan cada arma, para el número de la hoja.
  Map<String, int> armasDe(Selection unidad) => dataset.weaponCountsOf(unidad);

  /// Si esa anfitriona ya lleva otro de la misma clase. No lo impide: lo avisa.
  bool anfitrionOcupado(Selection lider, Selection anfitrion) =>
      roster.hostAlreadyLed(lider, anfitrion);

  /// Si de ese grupo hay que elegir algo sí o sí, que es lo que impide dejarlo vacío.
  bool esObligatorio(Selection padre, OptionGroup grupo) {
    final uso = roster.groupUsage(padre, grupo);
    return (uso.minimo ?? 0) > 0;
  }

  /// La hoja de datos de lo que esta unidad lleva puesto, no de todo lo que podría llevar.
  List<Profile> hojaDe(Selection unidad) => dataset.sheetOfSelection(unidad);

  /// Si ese grupo decide cuántas miniaturas tiene la unidad.
  bool esGrupoDeMiniaturas(Selection unidad, OptionGroup grupo) =>
      roster.isModelGroup(unidad, grupo);

  /// La miniatura de relleno de un grupo: la que hace bulto y a la que se le cambia el arma.
  Selection? rellenoDe(Selection unidad, OptionGroup grupo) =>
      roster.defaultOptionFor(unidad, grupo);

  bool esRelleno(Selection unidad, Selection opcion) => roster.isFiller(unidad, opcion);

  /// De qué escuadra sale una opción: su grupo, o el que lo contiene.
  OptionGroup? grupoDeMiniaturasDe(Selection unidad, Selection opcion) =>
      roster.modelGroupOf(unidad, opcion);

  /// Le cambia el arma a una miniatura. No hace crecer la escuadra: le quita el bólter a una.
  void asignarArma(Selection unidad, Selection opcion) {
    _apunta();
    roster.assign(unidad, opcion);
    notifyListeners();
  }

  /// Le devuelve el arma de serie a una miniatura.
  void devolverArma(Selection unidad, Selection opcion) {
    _apunta();
    roster.unassign(unidad, opcion);
    notifyListeners();
  }

  bool sePuedeAsignar(Selection unidad, Selection opcion) =>
      roster.canAssign(unidad, opcion);

  /// A cuántas miniaturas se les puede poner esa arma como mucho, ahora mismo.
  int? topeDeArma(Selection unidad, Selection opcion) =>
      roster.effectiveMaxOf(unidad, opcion);

  /// Mete una miniatura más en la escuadra: el soldado raso, no el sargento.
  void anadirMiniatura(Selection unidad, OptionGroup grupo) {
    final opcion = roster.defaultOptionFor(unidad, grupo);
    if (opcion == null || !roster.canAdd(unidad, opcion)) return;
    anadirOpcion(unidad, opcion);
  }

  /// Si cabe otra miniatura: lo dice el techo del grupo, no el de una opción suelta.
  bool cabeOtraMiniatura(Selection unidad, OptionGroup grupo) {
    final uso = roster.groupUsage(unidad, grupo);
    if (uso.maximo != null && uso.puestas >= uso.maximo!) return false;
    final opcion = roster.defaultOptionFor(unidad, grupo);
    return opcion != null && roster.canAdd(unidad, opcion);
  }

  /// Quita una miniatura, del montón más grande que se pueda tocar.
  ///
  /// Del más grande y no del primero: quitando del primero se llevaría por delante al sargento,
  /// que es justo el que no se toca, o el arma especial que el jugador acaba de elegir.
  void quitarMiniatura(Selection unidad, OptionGroup grupo) {
    final victima = _miniaturaQueSobra(unidad, grupo);
    if (victima == null) return;
    quitarOpcion(unidad, victima);
  }

  bool sePuedeQuitarMiniatura(Selection unidad, OptionGroup grupo) {
    final uso = roster.groupUsage(unidad, grupo);
    if (uso.minimo != null && uso.puestas <= uso.minimo!) return false;
    return _miniaturaQueSobra(unidad, grupo) != null;
  }

  Selection? _miniaturaQueSobra(Selection unidad, OptionGroup grupo) {
    final delGrupo = roster
        .optionsFor(unidad)
        .where((o) => roster.modelGroupOf(unidad, o)?.id == grupo.id)
        .where((o) => unidad.cuantasDe(o) > 0)
        .where((o) => roster.canRemove(unidad, o, hayAlternativas: true))
        .toList();
    // Se quita primero del relleno: es la miniatura sin nada especial, y quitar antes la que
    // lleva el plasma sería deshacer una elección del jugador para hacer sitio.
    final relleno = delGrupo.where((o) => roster.isFiller(unidad, o)).firstOrNull;
    if (relleno != null) return relleno;
    delGrupo.sort((a, b) => unidad.cuantasDe(b).compareTo(unidad.cuantasDe(a)));
    return delGrupo.firstOrNull;
  }

  /// Cuántas cabe elegir de un grupo y cuántas hay, con los modifiers ya aplicados.
  ({int puestas, int? minimo, int? maximo}) usoDeGrupo(Selection padre, OptionGroup grupo) =>
      roster.groupUsage(padre, grupo);

  /// Quita una. Al llegar a cero desaparece la fila, que dejarla a cero ensucia la ficha.
  void quitarOpcion(Selection padre, Selection opcion) {
    _apunta();
    final puesta = padre.puestaDe(opcion);
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
