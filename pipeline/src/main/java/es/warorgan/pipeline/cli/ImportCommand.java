package es.warorgan.pipeline.cli;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.translation.TranslationBatch;
import es.warorgan.pipeline.translation.TranslationBatches;
import es.warorgan.pipeline.translation.TranslationUnit;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

/**
 * Incorpora traducciones a los lotes desde ficheros sueltos de {@code {"id": "traducción"}}.
 *
 * <p>Es la forma de recoger el trabajo cuando se traduce en paralelo: cada traductor entrega su
 * propio fichero y aquí se fusionan, en vez de que varios escriban a la vez sobre los mismos lotes.
 */
@Component
public class ImportCommand {

    private final TranslationBatches batches;
    private final PipelineProperties properties;
    private final ObjectMapper mapper = new ObjectMapper();

    public ImportCommand(TranslationBatches batches, PipelineProperties properties) {
        this.batches = batches;
        this.properties = properties;
    }

    public void run(List<String> paths) {
        if (paths.isEmpty()) {
            throw new IllegalArgumentException("Uso: import <fichero-o-directorio> [...]");
        }

        Map<String, String> incoming = new LinkedHashMap<>();
        for (Path file : expand(paths)) {
            try {
                incoming.putAll(mapper.readValue(file.toFile(), new TypeReference<Map<String, String>>() {
                }));
            } catch (IOException e) {
                throw new UncheckedIOException("No se pudo leer " + file, e);
            }
        }

        List<TranslationBatch> updated = new ArrayList<>();
        Set<String> known = new HashSet<>();
        int applied = 0;
        int overwritten = 0;
        for (TranslationBatch batch : batches.readAll(properties.translationsDir())) {
            batch.units().forEach(unit -> known.add(unit.id()));
            List<TranslationUnit> units = new ArrayList<>(batch.units().size());
            boolean touched = false;
            for (TranslationUnit unit : batch.units()) {
                String target = incoming.get(unit.id());
                if (target == null || target.isBlank() || target.equals(unit.target())) {
                    units.add(unit);
                    continue;
                }
                if (unit.target() != null && !unit.target().isBlank()) {
                    overwritten++;
                }
                units.add(new TranslationUnit(unit.id(), unit.kind(), unit.occurrences(),
                        unit.files(), unit.protect(), unit.source(), target));
                applied++;
                touched = true;
            }
            if (touched) {
                updated.add(new TranslationBatch(batch.batch(), units));
            }
        }
        updated.forEach(batch -> batches.write(properties.translationsDir(), batch));

        long unknown = incoming.keySet().stream().filter(id -> !known.contains(id)).count();
        System.out.printf("Traducciones leídas      %d%n", incoming.size());
        System.out.printf("Aplicadas                %d en %d lote(s)%n", applied, updated.size());
        if (overwritten > 0) {
            System.out.printf("Sustituidas              %d ya tenían traducción%n", overwritten);
        }
        if (unknown > 0) {
            System.out.printf("Ignoradas                %d con id desconocido%n", unknown);
        }
    }

    private List<Path> expand(List<String> paths) {
        List<Path> files = new ArrayList<>();
        for (String path : paths) {
            Path candidate = Path.of(path);
            if (Files.isDirectory(candidate)) {
                // Recursivo: las entregas se acaban organizando en subcarpetas por tanda.
                try (Stream<Path> entries = Files.walk(candidate)) {
                    entries.filter(Files::isRegularFile)
                            .filter(p -> p.getFileName().toString().endsWith(".json"))
                            .sorted()
                            .forEach(files::add);
                } catch (IOException e) {
                    throw new UncheckedIOException(e);
                }
            } else if (Files.isRegularFile(candidate)) {
                files.add(candidate);
            } else {
                throw new IllegalArgumentException("No existe: " + path);
            }
        }
        return files;
    }
}
