// Qué le queda mal al constructor, en las 36 facciones a la vez.
//
// Clasifica por patrón, no por unidad: lo que importa es si un fallo es sistemático —y entonces
// hay un arreglo que vale para todas— o si es una elección legítima del jugador.
import 'dart:io';
import 'package:warorgan_core/warorgan_core.dart';

Directory _dir() {
  final es = Directory('../data/bsdata-es');
  return es.existsSync() ? es : Directory('../data/bsdata');
}

void main() async {
  final dataset = await Dataset.load(_dir());
  final porTipo = <String, int>{};
  final ejemplos = <String, List<String>>{};
  var unidades = 0, conPendiente = 0;

  for (final faccion in dataset.factions) {
    final detachments = dataset.detachmentsOf(faccion);
    if (detachments.isEmpty) continue;
    for (final unidad in faccion.units) {
      final roster = Roster(faction: faccion, pointsLimit: 2000)
        ..detachments.add(detachments.first);
      final raiz = roster.selectionFor(unidad);
      roster.add(raiz);
      unidades++;
      final avisos = roster.validate();
      if (avisos.isEmpty) continue;
      conPendiente++;

      for (final v in avisos) {
        final tipo = _clasificar(roster, raiz, v);
        porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
        ejemplos.putIfAbsent(tipo, () => []);
        if (ejemplos[tipo]!.length < 3) {
          ejemplos[tipo]!.add('${_corto(faccion.name)} · ${unidad.name} · ${v.message}');
        }
      }
    }
  }

  print('unidades: $unidades · con algo pendiente: $conPendiente');
  print('');
  final orden = porTipo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in orden) {
    print('${e.value.toString().padLeft(5)}  ${e.key}');
    for (final x in ejemplos[e.key]!) {
      print('        $x');
    }
  }
}

/// Por qué queda pendiente: elección legítima, o algo que el motor debería haber resuelto.
String _clasificar(Roster roster, Selection raiz, Violation v) {
  final msg = v.message;
  if (msg.contains('como máximo')) return 'B · nace pasándose de un máximo';
  if (!msg.contains('mínimo')) return 'C · otro';

  // ¿El grupo que incumple declara una opción por defecto? Si la declara y sigue vacío, es un
  // fallo del motor. Si no la declara, el dataset quiere que elija el jugador.
  final dueno = v.selection;
  if (dueno == null) return 'C · otro';
  for (final g in dueno.groups) {
    final uso = roster.groupUsage(dueno, g);
    if (uso.minimo != null && uso.puestas < uso.minimo!) {
      final cuantas = roster
          .optionsFor(dueno)
          .where((o) => o.groupId == g.id)
          .length;
      if (cuantas == 0) return 'A · grupo obligatorio sin ninguna opción que ofrecer';
      return 'D · el jugador elige (el dataset no marca defecto)';
    }
  }
  return 'C · otro';
}

String _corto(String n) => n.split(' - ').last;
