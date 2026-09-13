package es.warorgan.pipeline.translation;

import java.util.List;

/**
 * Un texto único a traducir. El {@code id} es el hash del texto original, así que es estable entre
 * ejecuciones: cuando upstream cambia una frase, cambia su id y reaparece como pendiente sin tocar
 * lo ya traducido.
 *
 * @param protect nombres propios y keywords que deben quedarse en inglés dentro de este texto
 * @param target  la traducción; {@code null} mientras esté pendiente
 */
public record TranslationUnit(
        String id,
        String kind,
        int occurrences,
        List<String> files,
        Protection protect,
        String source,
        String target) {

    public record Protection(List<String> keywords, List<String> names) {
    }
}
