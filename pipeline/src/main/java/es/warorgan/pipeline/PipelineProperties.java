package es.warorgan.pipeline;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.file.Path;

/**
 * Rutas relativas a la raíz del repositorio: el pipeline se ejecuta desde ahí
 * ({@code mvn -f pipeline/pom.xml ...}).
 *
 * @param batchChars presupuesto de caracteres de texto original por lote de traducción
 */
@ConfigurationProperties(prefix = "warorgan")
public record PipelineProperties(
        Path sourceDir,
        Path spanishDir,
        Path translationsDir,
        int batchChars) {
}
