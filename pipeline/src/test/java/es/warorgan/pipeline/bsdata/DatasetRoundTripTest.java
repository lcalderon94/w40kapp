package es.warorgan.pipeline.bsdata;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assumptions.assumeThat;

/**
 * Comprueba sobre el dataset real que la sustitución por offsets es exacta: si cada literal se
 * reemplaza por su propio valor, el fichero tiene que quedar idéntico byte a byte. Es la garantía
 * de que traducir no puede alterar la estructura de BattleScribe.
 */
class DatasetRoundTripTest {

    private static final Path DATASET = Path.of("..", "data", "bsdata");

    private static final BsDataCatalog CATALOG = new BsDataCatalog();
    private static final TranslatableScanner SCANNER = new TranslatableScanner();
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static List<Path> files;
    private static Map<String, String> characteristicTypes;

    @BeforeAll
    static void loadDataset() {
        assumeThat(DATASET).as("dataset en data/bsdata").exists();
        files = CATALOG.files(DATASET);
        characteristicTypes = new HashMap<>();
        for (Path file : files) {
            CATALOG.collectCharacteristicTypes(SCANNER.parse(CATALOG.read(file)), characteristicTypes);
        }
    }

    @Test
    void reinyectarCadaTextoConSuPropioValorDejaElFicheroIntacto() throws Exception {
        int scanned = 0;
        for (Path file : files) {
            String raw = CATALOG.read(file);
            List<TranslatableText> texts = SCANNER.scan(file.getFileName().toString(), raw, characteristicTypes);
            scanned += texts.size();

            StringBuilder output = new StringBuilder(raw);
            for (int i = texts.size() - 1; i >= 0; i--) {
                TranslatableText text = texts.get(i);
                output.replace(text.literalStart(), text.literalEnd(), MAPPER.writeValueAsString(text.value()));
            }
            assertThat(output.toString())
                    .as("round-trip de %s", file.getFileName())
                    .isEqualTo(raw);
        }
        assertThat(scanned).as("textos traducibles encontrados").isGreaterThan(6000);
    }

    @Test
    void laSalidaTraducidaSigueSiendoJsonValido() throws Exception {
        Path file = files.get(0);
        String raw = CATALOG.read(file);
        List<TranslatableText> texts = SCANNER.scan(file.getFileName().toString(), raw, characteristicTypes);
        assumeThat(texts).isNotEmpty();

        StringBuilder output = new StringBuilder(raw);
        for (int i = texts.size() - 1; i >= 0; i--) {
            TranslatableText text = texts.get(i);
            output.replace(text.literalStart(), text.literalEnd(),
                    MAPPER.writeValueAsString("Acento y comillas: «" + text.value() + "» — ñ"));
        }
        assertThat(MAPPER.readTree(output.toString())).isNotNull();
    }
}
