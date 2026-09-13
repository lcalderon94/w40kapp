package es.warorgan.pipeline.cli;

import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.protect.RuleKeywords;
import es.warorgan.pipeline.translation.TranslationBatch;
import es.warorgan.pipeline.translation.TranslationBatches;
import es.warorgan.pipeline.translation.TranslationUnit;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * Revisa la memoria de traducción. Sobre miles de unidades, perder un **[TORRENT]** al traducir no
 * se ve a simple vista y cambia lo que el jugador lee, así que se comprueba que toda keyword entre
 * corchetes del original siga presente en la traducción.
 */
@Component
public class CheckCommand {

    private final TranslationBatches batches;
    private final PipelineProperties properties;

    public CheckCommand(TranslationBatches batches, PipelineProperties properties) {
        this.batches = batches;
        this.properties = properties;
    }

    public void run() {
        List<String> problems = new ArrayList<>();
        int translated = 0;
        for (TranslationBatch batch : batches.readAll(properties.translationsDir())) {
            for (TranslationUnit unit : batch.units()) {
                if (unit.target() == null || unit.target().isBlank()) {
                    continue;
                }
                translated++;
                Set<String> missing = RuleKeywords.in(unit.source());
                missing.removeAll(RuleKeywords.in(unit.target()));
                if (!missing.isEmpty()) {
                    problems.add("  lote %03d  %s  falta %s".formatted(batch.batch(), unit.id(), missing));
                }
                if (unit.target().equals(unit.source()) && unit.source().matches(".*\\p{L}{3}.*")) {
                    problems.add("  lote %03d  %s  sin traducir (target = source)".formatted(batch.batch(), unit.id()));
                }
            }
        }

        System.out.printf("Unidades traducidas      %d%n", translated);
        if (problems.isEmpty()) {
            System.out.println("Sin incidencias");
        } else {
            System.out.printf("Incidencias              %d%n", problems.size());
            problems.forEach(System.out::println);
            throw new IllegalStateException("La memoria de traducción tiene " + problems.size() + " incidencia(s)");
        }
    }
}
