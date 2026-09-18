import 'package:flutter/material.dart';
import 'package:warorgan_core/warorgan_core.dart';

import '../estado/lista_en_curso.dart';
import '../tema.dart';
import '../widgets/texto_reglas.dart';

/// Elegir detachment, que es la decisión que más condiciona la lista.
///
/// Se enseña la regla entera y las mejoras que habilita, porque es justo lo que se compara al
/// decidir: un detachment no se elige por el nombre sino por lo que da.
class PantallaDeElegirDetachment extends StatelessWidget {
  const PantallaDeElegirDetachment({super.key, required this.lista});

  final ListaEnCurso lista;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: lista,
      builder: (context, _) {
        final detachments = lista.detachmentsDisponibles;
        final uso = lista.puntosDeDetachment;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detachment'),
            actions: [
              if (uso.presupuesto != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text('${uso.gastados}/${uso.presupuesto} DP',
                        style: TextStyle(
                            color: uso.gastados > uso.presupuesto!
                                ? Tema.aviso
                                : Tema.acento,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
          body: detachments.isEmpty
              ? const Center(
                  child: Text('Esta facción no declara detachments',
                      style: TextStyle(color: Tema.textoTenue)))
              : ListView.separated(
                  itemCount: detachments.length,
                  separatorBuilder: (_, __) =>
                      const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (context, i) =>
                      _Detachment(lista: lista, detachment: detachments[i]),
                ),
        );
      },
    );
  }
}

class _Detachment extends StatelessWidget {
  const _Detachment({required this.lista, required this.detachment});

  final ListaEnCurso lista;
  final Detachment detachment;

  @override
  Widget build(BuildContext context) {
    final elegido = lista.tieneDetachment(detachment);
    final cabe = lista.cabeDetachment(detachment);
    final mejoras = lista.dataset
        .enhancementsOf(lista.faccion, detachmentId: detachment.id);

    // Se elige tocando la fila. Antes había que desplegarla, leer y buscar un botón «Añadir» al
    // final: tres gestos para lo que es una elección de una. La regla y las mejoras siguen ahí,
    // detrás de la flecha, para cuando se quiera comparar antes de decidir.
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('detachment-${detachment.id}'),
        tilePadding: const EdgeInsets.only(left: 8, right: 12),
        leading: IconButton(
          key: ValueKey('elegir-${detachment.id}'),
          onPressed: !elegido && !cabe ? null : () => lista.alternarDetachment(detachment),
          icon: Icon(
              elegido ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 26),
          color: Tema.acento,
          disabledColor: Tema.textoTenue.withValues(alpha: 0.35),
          tooltip: elegido
              ? 'Quitar'
              : cabe
                  ? 'Elegir'
                  : 'No caben sus ${detachment.detachmentPoints} DP',
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !elegido && !cabe ? null : () => lista.alternarDetachment(detachment),
          child: Row(
            children: [
              Expanded(
                child: Text(detachment.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: elegido ? Tema.acento : Tema.texto)),
              ),
              if (detachment.detachmentPoints > 0)
                Text('${detachment.detachmentPoints} DP',
                    style: TextStyle(
                        color: !elegido && !cabe ? Tema.aviso : Tema.textoTenue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        subtitle: detachment.ruleName == null
            ? null
            : Text(detachment.ruleName!,
                style: const TextStyle(color: Tema.textoTenue, fontSize: 13)),
        iconColor: Tema.acento,
        collapsedIconColor: Tema.textoTenue,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detachment.rule != null) TextoDeRegla(detachment.rule!),
          if (mejoras.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('MEJORAS',
                style: TextStyle(
                    color: Tema.acento,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3)),
            const SizedBox(height: 6),
            for (final mejora in mejoras)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${mejora.name} · ${mejora.points} pts',
                    style: const TextStyle(fontSize: 13, color: Tema.textoTenue)),
              ),
          ],
          if (!elegido && !cabe)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'No caben sus ${detachment.detachmentPoints} DP en lo que queda',
                  style: const TextStyle(color: Tema.aviso, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
