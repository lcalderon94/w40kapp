package es.warorgan.pipeline.protect;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ProperNameIndexTest {

    private final ProperNameIndex index = new ProperNameIndex(List.of(
            "Chaos", "Chaos Lord", "Poxwalkers", "Blast", "Plague spewer", "Death Guard"));

    @Test
    void detectaElNombreMasLargoEnCadaPosicion() {
        assertThat(index.matchesIn("The Chaos Lord leads the unit."))
                .containsExactly("Chaos Lord");
    }

    @Test
    void distingueMayusculasParaNoConfundirNombreConPalabraCorriente() {
        assertThat(index.matchesIn("Each time a blast weapon is fired")).isEmpty();
        assertThat(index.matchesIn("Each time a [BLAST] weapon is fired, Blast applies"))
                .containsExactly("Blast");
    }

    @Test
    void exigeLimiteDePalabra() {
        assertThat(index.matchesIn("Poxwalkersss are not a unit")).isEmpty();
        assertThat(index.matchesIn("Poxwalkers, and others")).containsExactly("Poxwalkers");
    }

    @Test
    void encuentraVariosNombresEnElMismoTexto() {
        assertThat(index.matchesIn("The Plague spewer of the Death Guard"))
                .containsExactly("Plague spewer", "Death Guard");
    }

    @Test
    void extraeLasKeywordsEntreCorchetes() {
        assertThat(RuleKeywords.in("Attacks with **[SUSTAINED HITS 2]** and [LETHAL HITS] hit harder"))
                .containsExactly("[SUSTAINED HITS 2]", "[LETHAL HITS]");
    }
}
