package es.warorgan.pipeline.cli;

import com.fasterxml.jackson.databind.JsonNode;
import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.bsdata.BsDataCatalog;
import es.warorgan.pipeline.bsdata.TranslatableScanner;
import es.warorgan.pipeline.protect.ProperNameIndex;
import es.warorgan.pipeline.protect.RuleKeywords;
import es.warorgan.pipeline.translation.TranslationBatch;
import es.warorgan.pipeline.translation.TranslationBatches;
import es.warorgan.pipeline.translation.TranslationUnit;
import org.springframework.stereotype.Component;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Revisa la memoria de traducción. Sobre miles de unidades, perder un **[TORRENT]** al traducir no
 * se ve a simple vista y cambia lo que el jugador lee, así que se comprueba que toda keyword entre
 * corchetes del original siga presente en la traducción.
 */
@Component
public class CheckCommand {

    /** Mecánicas con nombre propio que el dataset no declara como regla pero deben seguir en inglés. */
    private static final List<String> EXTRA_GLOSSARY = List.of(
            "Battle-shock", "Battle-shocked", "Marked for Greatness", "Desperate Escape",
            "Rapid Ingress", "Teleport Homer", "Psychic Fortitude");

    /** Una palabra en minúscula delata prosa: un texto que es solo un nombre propio no cambia al traducirse. */
    private static final Pattern PROSA = Pattern.compile("\\b\\p{Ll}{3,}");

    private final BsDataCatalog catalog;
    private final TranslatableScanner scanner;
    private final TranslationBatches batches;
    private final PipelineProperties properties;

    public CheckCommand(BsDataCatalog catalog, TranslatableScanner scanner,
                        TranslationBatches batches, PipelineProperties properties) {
        this.catalog = catalog;
        this.scanner = scanner;
        this.batches = batches;
        this.properties = properties;
    }

    public void run() {
        ProperNameIndex glossary = new ProperNameIndex(glossaryTerms());
        List<String> problems = new ArrayList<>();
        List<String> warnings = new ArrayList<>();
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
                if (unit.target().equals(unit.source()) && PROSA.matcher(unit.source()).find()) {
                    problems.add("  lote %03d  %s  sin traducir (target = source)".formatted(batch.batch(), unit.id()));
                }

                Set<String> lostNames = glossary.matchesIn(unit.source());
                lostNames.removeAll(glossary.matchesIn(unit.target()));
                if (!lostNames.isEmpty()) {
                    warnings.add("  lote %03d  %s  ¿traducido? %s".formatted(batch.batch(), unit.id(), lostNames));
                }
            }
        }

        System.out.printf("Unidades traducidas      %d%n", translated);
        if (!warnings.isEmpty()) {
            System.out.printf("Nombres del glosario que desaparecen en la traducción  %d%n", warnings.size());
            warnings.forEach(System.out::println);
        }
        if (problems.isEmpty()) {
            System.out.println("Sin incidencias");
        } else {
            System.out.printf("Incidencias              %d%n", problems.size());
            problems.forEach(System.out::println);
            throw new IllegalStateException("La memoria de traducción tiene " + problems.size() + " incidencia(s)");
        }
    }

    /** Nombres de las reglas del game system, que son el glosario que la app enlaza, más los extra. */
    private List<String> glossaryTerms() {
        List<String> terms = new ArrayList<>(EXTRA_GLOSSARY);
        JsonNode gameSystem = null;
        for (Path file : catalog.files(properties.sourceDir())) {
            JsonNode tree = scanner.parse(catalog.read(file));
            if (tree.has("gameSystem")) {
                gameSystem = tree.get("gameSystem");
                break;
            }
        }
        if (gameSystem != null) {
            for (JsonNode rule : gameSystem.withArray("sharedRules")) {
                JsonNode name = rule.get("name");
                if (name != null) {
                    terms.add(name.asText());
                }
            }
        }
        return terms;
    }
}
