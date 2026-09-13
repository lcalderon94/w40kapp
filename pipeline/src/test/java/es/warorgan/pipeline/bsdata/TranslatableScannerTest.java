package es.warorgan.pipeline.bsdata;

import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class TranslatableScannerTest {

    private static final String FIXTURE = """
            {
              "catalogue": {
                "name": "Test",
                "comment": "nota interna del mantenedor",
                "profileTypes": [
                  {"id": "pt1", "name": "Abilities", "characteristicTypes": [
                    {"id": "ct-desc", "name": "Description"},
                    {"id": "ct-kw", "name": "Keywords"}
                  ]}
                ],
                "sharedProfiles": [
                  {"name": "Chaos Lord", "characteristics": [
                    {"name": "Description", "$text": "Re-roll a Hit roll of 1."},
                    {"name": "Keywords", "$text": "Infantry, Character"},
                    {"name": "M", "$text": "6\\""}
                  ]}
                ],
                "sharedRules": [
                  {"name": "Torrent", "description": "That attack automatically hits."}
                ],
                "sharedSelectionEntries": [
                  {"name": "Bearer", "modifiers": [
                    {"type": "set", "field": "ct-desc", "value": "This model has the Lone Operative ability."},
                    {"type": "set", "field": "ct-kw", "value": "Anti-Infantry 3+"},
                    {"type": "set", "field": "hidden", "value": "false"}
                  ]}
                ]
              }
            }
            """;

    private final TranslatableScanner scanner = new TranslatableScanner();
    private final BsDataCatalog catalog = new BsDataCatalog();

    private List<TranslatableText> scan() {
        Map<String, String> types = new HashMap<>();
        catalog.collectCharacteristicTypes(scanner.parse(FIXTURE), types);
        return scanner.scan("Test", FIXTURE, types);
    }

    @Test
    void extraeSoloLaProsaVisibleParaElJugador() {
        assertThat(scan()).extracting(TranslatableText::value).containsExactlyInAnyOrder(
                "Re-roll a Hit roll of 1.",
                "That attack automatically hits.",
                "This model has the Lone Operative ability.");
    }

    @Test
    void etiquetaElOrigenDeCadaTexto() {
        assertThat(scan()).extracting(TranslatableText::kind).containsExactlyInAnyOrder(
                "characteristic:Description", "rule", "modifier:Description");
    }

    @Test
    void losOffsetsDelimitanElLiteralCompleto() {
        for (TranslatableText text : scan()) {
            String literal = FIXTURE.substring(text.literalStart(), text.literalEnd());
            assertThat(literal).startsWith("\"").endsWith("\"");
            assertThat(literal).isEqualTo('"' + text.value() + '"');
        }
    }
}
