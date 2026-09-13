package es.warorgan.pipeline.cli;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.bsdata.BsDataCatalog;
import es.warorgan.pipeline.bsdata.TranslatableScanner;
import es.warorgan.pipeline.bsdata.TranslatableText;
import es.warorgan.pipeline.translation.TranslationBatches;
import org.springframework.stereotype.Component;

import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Reinyecta las traducciones sobre el dataset original y escribe la versión en español.
 *
 * <p>No re-serializa el JSON: sustituye cada literal traducido en su posición dentro del fichero
 * original, de modo que la estructura y el formato de BattleScribe quedan intactos y el diff contra
 * el inglés son solo los textos.
 */
@Component
public class ApplyCommand {

    private final BsDataCatalog catalog;
    private final TranslatableScanner scanner;
    private final TranslationBatches batches;
    private final PipelineProperties properties;
    private final ObjectMapper mapper = new ObjectMapper();

    public ApplyCommand(BsDataCatalog catalog, TranslatableScanner scanner,
                        TranslationBatches batches, PipelineProperties properties) {
        this.catalog = catalog;
        this.scanner = scanner;
        this.batches = batches;
        this.properties = properties;
    }

    public void run() {
        List<Path> files = catalog.files(properties.sourceDir());
        Map<String, String> translations = batches.translations(properties.translationsDir());

        Map<String, String> characteristicTypes = new HashMap<>();
        for (Path file : files) {
            JsonNode tree = scanner.parse(catalog.read(file));
            catalog.collectCharacteristicTypes(tree, characteristicTypes);
        }

        int total = 0;
        int applied = 0;
        for (Path file : files) {
            String name = file.getFileName().toString();
            String raw = catalog.read(file);
            List<TranslatableText> texts = scanner.scan(name, raw, characteristicTypes);

            StringBuilder output = new StringBuilder(raw);
            for (int i = texts.size() - 1; i >= 0; i--) {
                TranslatableText text = texts.get(i);
                total++;
                String target = translations.get(ExtractCommand.idOf(text.value()));
                if (target != null) {
                    applied++;
                    output.replace(text.literalStart(), text.literalEnd(), literal(target));
                }
            }
            catalog.write(properties.spanishDir().resolve(name), output.toString());
        }

        int percentage = total == 0 ? 0 : Math.round(applied * 100f / total);
        System.out.printf("Ficheros escritos        %d en %s%n", files.size(), properties.spanishDir());
        System.out.printf("Textos traducidos        %d de %d (%d%%)%n", applied, total, percentage);
        if (applied < total) {
            System.out.printf("Pendientes               %d texto(s) siguen en inglés%n", total - applied);
        }
    }

    private String literal(String value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("No se pudo escapar la traducción", e);
        }
    }
}
