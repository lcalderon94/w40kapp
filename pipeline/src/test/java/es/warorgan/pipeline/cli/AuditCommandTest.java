package es.warorgan.pipeline.cli;

import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.bsdata.BsDataCatalog;
import es.warorgan.pipeline.bsdata.TranslatableScanner;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assumptions.assumeThat;

/**
 * Pasa la auditoría sobre el dataset real. Si upstream introduce una referencia rota o una facción
 * deja de resolver unidades, este test falla antes de que el dato llegue a la app.
 */
class AuditCommandTest {

    private static final Path DATASET = Path.of("..", "data", "bsdata");

    @Test
    void elDatasetSirveParaConstruirListas() {
        assumeThat(DATASET).as("dataset en data/bsdata").exists();
        PipelineProperties properties = new PipelineProperties(
                DATASET, Path.of("target/es"), Path.of("target/translations"), 40000);
        AuditCommand audit = new AuditCommand(new BsDataCatalog(), new TranslatableScanner(), properties);
        assertThatCode(audit::run).doesNotThrowAnyException();
    }
}
