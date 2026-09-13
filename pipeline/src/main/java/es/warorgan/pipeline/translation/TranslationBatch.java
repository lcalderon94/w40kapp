package es.warorgan.pipeline.translation;

import java.util.List;

public record TranslationBatch(int batch, List<TranslationUnit> units) {
}
