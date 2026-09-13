package es.warorgan.pipeline.cli;

import com.fasterxml.jackson.databind.JsonNode;
import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.bsdata.BsDataCatalog;
import es.warorgan.pipeline.bsdata.TranslatableScanner;
import es.warorgan.pipeline.bsdata.TranslatableText;
import es.warorgan.pipeline.protect.ProperNameIndex;
import es.warorgan.pipeline.protect.RuleKeywords;
import es.warorgan.pipeline.translation.TranslationBatch;
import es.warorgan.pipeline.translation.TranslationBatches;
import es.warorgan.pipeline.translation.TranslationUnit;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/** Extrae los textos traducibles, los deduplica y escribe lotes para lo que aún no está traducido. */
@Component
public class ExtractCommand {

    private static final int MAX_CONTEXT_FILES = 3;

    private final BsDataCatalog catalog;
    private final TranslatableScanner scanner;
    private final TranslationBatches batches;
    private final PipelineProperties properties;

    public ExtractCommand(BsDataCatalog catalog, TranslatableScanner scanner,
                          TranslationBatches batches, PipelineProperties properties) {
        this.catalog = catalog;
        this.scanner = scanner;
        this.batches = batches;
        this.properties = properties;
    }

    public void run() {
        List<Path> files = catalog.files(properties.sourceDir());

        Map<String, String> characteristicTypes = new HashMap<>();
        Set<String> properNames = new TreeSet<>();
        for (Path file : files) {
            JsonNode tree = scanner.parse(catalog.read(file));
            catalog.collectCharacteristicTypes(tree, characteristicTypes);
            catalog.collectNames(tree, properNames);
        }
        ProperNameIndex nameIndex = new ProperNameIndex(properNames);

        Map<String, Aggregate> unique = new LinkedHashMap<>();
        int occurrences = 0;
        for (Path file : files) {
            String label = label(file);
            for (TranslatableText text : scanner.scan(label, catalog.read(file), characteristicTypes)) {
                occurrences++;
                unique.computeIfAbsent(idOf(text.value()), id -> new Aggregate(text.value(), text.kind()))
                        .add(label);
            }
        }

        List<TranslationBatch> existing = batches.readAll(properties.translationsDir());
        Set<String> known = new HashSet<>();
        int translated = 0;
        int highestBatch = 0;
        for (TranslationBatch batch : existing) {
            highestBatch = Math.max(highestBatch, batch.batch());
            for (TranslationUnit unit : batch.units()) {
                known.add(unit.id());
                if (unit.target() != null && !unit.target().isBlank()) {
                    translated++;
                }
            }
        }

        List<TranslationUnit> pending = new ArrayList<>();
        unique.forEach((id, aggregate) -> {
            if (!known.contains(id)) {
                pending.add(aggregate.toUnit(id, nameIndex));
            }
        });

        int written = writeBatches(pending, highestBatch);
        long orphans = known.stream().filter(id -> !unique.containsKey(id)).count();

        System.out.printf("Ficheros leídos          %d%n", files.size());
        System.out.printf("Textos traducibles       %d (%d únicos)%n", occurrences, unique.size());
        System.out.printf("Ya traducidos            %d%n", translated);
        System.out.printf("Pendientes nuevos        %d en %d lote(s)%n", pending.size(), written);
        System.out.printf("Nombres propios          %d%n", properNames.size());
        if (orphans > 0) {
            System.out.printf("Huérfanos en los lotes   %d (el texto ya no está en el dataset)%n", orphans);
        }
    }

    private int writeBatches(List<TranslationUnit> pending, int highestBatch) {
        int number = highestBatch;
        int budget = 0;
        List<TranslationUnit> current = new ArrayList<>();
        for (TranslationUnit unit : pending) {
            if (!current.isEmpty() && budget + unit.source().length() > properties.batchChars()) {
                batches.write(properties.translationsDir(), new TranslationBatch(++number, current));
                current = new ArrayList<>();
                budget = 0;
            }
            current.add(unit);
            budget += unit.source().length();
        }
        if (!current.isEmpty()) {
            batches.write(properties.translationsDir(), new TranslationBatch(++number, current));
        }
        return number - highestBatch;
    }

    private static String label(Path file) {
        String name = file.getFileName().toString();
        return name.substring(0, name.length() - ".json".length());
    }

    static String idOf(String source) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(source.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                hex.append(String.format("%02x", digest[i]));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static final class Aggregate {
        private final String source;
        private final String kind;
        private final Set<String> files = new LinkedHashSet<>();
        private int count;

        private Aggregate(String source, String kind) {
            this.source = source;
            this.kind = kind;
        }

        private void add(String file) {
            files.add(file);
            count++;
        }

        private TranslationUnit toUnit(String id, ProperNameIndex nameIndex) {
            TranslationUnit.Protection protection = new TranslationUnit.Protection(
                    List.copyOf(RuleKeywords.in(source)),
                    List.copyOf(nameIndex.matchesIn(source)));
            return new TranslationUnit(id, kind, count,
                    files.stream().limit(MAX_CONTEXT_FILES).toList(), protection, source, null);
        }
    }
}
