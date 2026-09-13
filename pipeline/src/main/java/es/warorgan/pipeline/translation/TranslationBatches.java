package es.warorgan.pipeline.translation;

import com.fasterxml.jackson.core.util.DefaultIndenter;
import com.fasterxml.jackson.core.util.DefaultPrettyPrinter;
import com.fasterxml.jackson.core.util.Separators;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.ObjectWriter;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

/**
 * Los lotes de traducción, que son a la vez la unidad de trabajo y la memoria de traducción: se
 * generan con {@code target} a null, se rellenan, y se versionan en el repositorio.
 */
@Component
public class TranslationBatches {

    private static final String PREFIX = "batch-";
    private static final String SUFFIX = ".json";

    private final ObjectMapper mapper = new ObjectMapper();
    private final ObjectWriter writer;

    public TranslationBatches() {
        DefaultIndenter indenter = new DefaultIndenter("  ", "\n");
        DefaultPrettyPrinter printer = new DefaultPrettyPrinter()
                .withSeparators(Separators.createDefaultInstance()
                        .withObjectFieldValueSpacing(Separators.Spacing.AFTER)
                        .withObjectEmptySeparator("")
                        .withArrayEmptySeparator(""));
        printer.indentObjectsWith(indenter);
        printer.indentArraysWith(indenter);
        this.writer = mapper.writer(printer);
    }

    public List<TranslationBatch> readAll(Path directory) {
        if (!Files.isDirectory(directory)) {
            return List.of();
        }
        try (Stream<Path> entries = Files.list(directory)) {
            List<Path> files = entries
                    .filter(path -> {
                        String name = path.getFileName().toString();
                        return name.startsWith(PREFIX) && name.endsWith(SUFFIX);
                    })
                    .sorted(Comparator.comparing(path -> path.getFileName().toString()))
                    .toList();
            List<TranslationBatch> batches = new ArrayList<>(files.size());
            for (Path file : files) {
                batches.add(mapper.readValue(file.toFile(), TranslationBatch.class));
            }
            return batches;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** id a traducción, solo de las unidades ya resueltas. */
    public Map<String, String> translations(Path directory) {
        Map<String, String> translations = new LinkedHashMap<>();
        for (TranslationBatch batch : readAll(directory)) {
            for (TranslationUnit unit : batch.units()) {
                if (unit.target() != null && !unit.target().isBlank()) {
                    translations.put(unit.id(), unit.target());
                }
            }
        }
        return translations;
    }

    public void write(Path directory, TranslationBatch batch) {
        Path file = directory.resolve(PREFIX + String.format("%03d", batch.batch()) + SUFFIX);
        try {
            Files.createDirectories(directory);
            Files.writeString(file, writer.writeValueAsString(batch) + "\n", StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
