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

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(detachment.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: elegido ? Tema.acento : Tema.texto)),
            ),
            if (detachment.detachmentPoints > 0)
              Text('${detachment.detachmentPoints} DP',
                  style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
          ],
        ),
        subtitle: detachment.ruleName == null
            ? null
            : Text(detachment.ruleName!,
                style: const TextStyle(color: Tema.textoTenue, fontSize: 12)),
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
          const SizedBox(height: 14),
          // En 11ª caben varios detachments: lo que los limita es el presupuesto de Detachment
          // Points, no un «elige uno». A 2000 puntos son tres, y Tallyband Summoners cuesta dos,
          // así que queda uno por gastar y hay que poder gastarlo.
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: elegido ? Tema.superficieAlta : Tema.acento,
                foregroundColor: elegido ? Tema.texto : Tema.fondo,
                disabledBackgroundColor: Tema.superficieAlta,
                disabledForegroundColor: Tema.textoTenue,
              ),
              onPressed: !elegido && !cabe
                  ? null
                  : () => lista.alternarDetachment(detachment),
              child: Text(elegido
                  ? 'Quitar'
                  : cabe
                      ? 'Añadir'
                      : 'No caben sus ${detachment.detachmentPoints} DP'),
            ),
          ),
        ],
      ),
    );
  }
}
