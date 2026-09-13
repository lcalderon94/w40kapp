package es.warorgan.pipeline.bsdata;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

/** Acceso a los ficheros del dataset y a los índices globales que necesita el escaneo. */
@Component
public class BsDataCatalog {

    public List<Path> files(Path directory) {
        if (!Files.isDirectory(directory)) {
            throw new IllegalArgumentException("No existe el directorio del dataset: " + directory);
        }
        try (Stream<Path> entries = Files.list(directory)) {
            List<Path> files = entries
                    .filter(p -> p.getFileName().toString().endsWith(".json"))
                    .sorted(Comparator.comparing(p -> p.getFileName().toString()))
                    .toList();
            if (files.isEmpty()) {
                throw new IllegalArgumentException("El dataset no tiene ficheros JSON: " + directory);
            }
            return files;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public String read(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public void write(Path file, String content) {
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, content, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Recopila los characteristicType declarados en un fichero: su id es lo que apunta un modifier. */
    public void collectCharacteristicTypes(JsonNode node, Map<String, String> into) {
        if (node.isArray()) {
            node.forEach(child -> collectCharacteristicTypes(child, into));
            return;
        }
        if (!node.isObject()) {
            return;
        }
        JsonNode profileTypes = node.get("profileTypes");
        if (profileTypes != null && profileTypes.isArray()) {
            for (JsonNode profileType : profileTypes) {
                JsonNode types = profileType.get("characteristicTypes");
                if (types != null && types.isArray()) {
                    for (JsonNode type : types) {
                        JsonNode id = type.get("id");
                        JsonNode name = type.get("name");
                        if (id != null && name != null) {
                            into.put(id.asText(), name.asText());
                        }
                    }
                }
            }
        }
        node.fields().forEachRemaining(entry -> collectCharacteristicTypes(entry.getValue(), into));
    }

    /** Todos los valores de {@code name}: los nombres propios que no se traducen. */
    public void collectNames(JsonNode node, Set<String> into) {
        if (node.isArray()) {
            node.forEach(child -> collectNames(child, into));
            return;
        }
        if (!node.isObject()) {
            return;
        }
        node.fields().forEachRemaining(entry -> {
            JsonNode value = entry.getValue();
            if ("name".equals(entry.getKey()) && value.isTextual() && !value.asText().isBlank()) {
                into.add(value.asText());
            } else {
                collectNames(value, into);
            }
        });
    }

}
