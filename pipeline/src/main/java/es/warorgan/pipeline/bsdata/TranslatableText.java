package es.warorgan.pipeline.bsdata;

/**
 * Un texto traducible localizado dentro de un fichero, con la posición exacta de su literal JSON.
 * {@code literalStart} apunta a la comilla de apertura y {@code literalEnd} al carácter siguiente
 * a la de cierre, de modo que reemplazar ese tramo deja intacto el resto del fichero.
 */
public record TranslatableText(
        String file,
        String pointer,
        String kind,
        String value,
        int literalStart,
        int literalEnd) {
}
