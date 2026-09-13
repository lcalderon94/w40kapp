package es.warorgan.pipeline.cli;

import com.fasterxml.jackson.databind.JsonNode;
import es.warorgan.pipeline.PipelineProperties;
import es.warorgan.pipeline.bsdata.BsDataCatalog;
import es.warorgan.pipeline.bsdata.TranslatableScanner;
import org.springframework.stereotype.Component;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * Comprueba que el dataset siga sirviendo para construir listas, que es lo que la app necesita de
 * él. Está pensado para pasarlo tras refrescar desde upstream: BSData se actualiza a diario y una
 * referencia rota o una facción que deja de resolver unidades no se ve leyendo el JSON, pero deja
 * la app inservible.
 *
 * <p>Verifica tres cosas:
 * <ol>
 *   <li>Que todo {@code targetId} apunte a algo que existe en el conjunto de los 46 ficheros.</li>
 *   <li>Que cada facción jugable resuelva su lista de unidades. Las suyas propias más las que
 *       hereda de los catálogos que enlaza con {@code importRootEntries}: sin eso, cada capítulo de
 *       Space Marines se queda en cero unidades.</li>
 *   <li>Que cada unidad tenga coste en puntos en algún punto de su árbol. El coste no está siempre
 *       en la unidad: a veces vive en la miniatura que cuelga de ella.</li>
 * </ol>
 */
@Component
public class AuditCommand {

    private static final String PUNTOS = "51b2-306e-1021-d207";

    private final BsDataCatalog catalog;
    private final TranslatableScanner scanner;
    private final PipelineProperties properties;

    public AuditCommand(BsDataCatalog catalog, TranslatableScanner scanner, PipelineProperties properties) {
        this.catalog = catalog;
        this.scanner = scanner;
        this.properties = properties;
    }

    public void run() {
        Map<String, JsonNode> porId = new HashMap<>();
        Map<String, JsonNode> catalogos = new LinkedHashMap<>();
        for (Path file : catalog.files(properties.sourceDir())) {
            JsonNode raiz = scanner.parse(catalog.read(file));
            JsonNode nodo = raiz.fields().next().getValue();
            String nombre = file.getFileName().toString();
            catalogos.put(nombre.substring(0, nombre.length() - ".json".length()), nodo);
            indexar(raiz, porId);
        }

        List<String> problemas = new ArrayList<>();
        int referencias = contarReferencias(catalogos.values(), porId, problemas);

        Set<String> distintas = new TreeSet<>();
        Set<String> sinPuntos = new TreeSet<>();
        int facciones = 0;
        int unidades = 0;
        for (Map.Entry<String, JsonNode> entrada : catalogos.entrySet()) {
            JsonNode nodo = entrada.getValue();
            if (!nodo.path("type").asText().equals("catalogue") || nodo.path("library").asBoolean()) {
                continue;
            }
            facciones++;
            List<JsonNode> unidadesFaccion = unidadesDe(nodo, porId, new HashSet<>());
            if (unidadesFaccion.isEmpty()) {
                problemas.add("  %s no resuelve ninguna unidad".formatted(entrada.getKey()));
                continue;
            }
            unidades += unidadesFaccion.size();
            for (JsonNode unidad : unidadesFaccion) {
                distintas.add(unidad.path("name").asText());
                if (!tienePuntos(unidad, porId, new HashSet<>())) {
                    sinPuntos.add(unidad.path("name").asText());
                }
            }
        }

        System.out.printf("Identificadores          %d%n", porId.size());
        System.out.printf("Referencias resueltas    %d%n", referencias);
        System.out.printf("Facciones jugables       %d%n", facciones);
        System.out.printf("Unidades seleccionables  %d (%d distintas)%n", unidades, distintas.size());
        if (!sinPuntos.isEmpty()) {
            // No es un fallo: hay contenido Legends y unidades gratuitas que no llevan puntos.
            // La app tiene que saber mostrarlas a 0, así que conviene tenerlas localizadas.
            System.out.printf("Sin coste en puntos      %d unidad(es): %s%n", sinPuntos.size(), sinPuntos);
        }
        if (problemas.isEmpty()) {
            System.out.println("Sin incidencias");
        } else {
            System.out.printf("Incidencias              %d%n", problemas.size());
            problemas.stream().limit(25).forEach(System.out::println);
            throw new IllegalStateException("El dataset tiene " + problemas.size() + " incidencia(s)");
        }
    }

    private int contarReferencias(Iterable<JsonNode> nodos, Map<String, JsonNode> porId, List<String> problemas) {
        int[] total = {0};
        for (JsonNode nodo : nodos) {
            recorrer(nodo, hijo -> {
                JsonNode destino = hijo.get("targetId");
                if (destino != null && destino.isTextual()) {
                    total[0]++;
                    if (!porId.containsKey(destino.asText())) {
                        problemas.add("  referencia rota: %s -> %s"
                                .formatted(hijo.path("name").asText("?"), destino.asText()));
                    }
                }
            });
        }
        return total[0];
    }

    /** Entradas raíz de la facción: las propias más las heredadas por importRootEntries. */
    private List<JsonNode> unidadesDe(JsonNode catalogo, Map<String, JsonNode> porId, Set<String> visitados) {
        List<JsonNode> unidades = new ArrayList<>();
        if (!visitados.add(catalogo.path("id").asText())) {
            return unidades;
        }
        for (JsonNode enlace : catalogo.withArray("entryLinks")) {
            JsonNode destino = porId.get(enlace.path("targetId").asText());
            if (destino != null && esUnidad(destino)) {
                unidades.add(destino);
            }
        }
        for (JsonNode enlace : catalogo.withArray("catalogueLinks")) {
            if (enlace.path("importRootEntries").asBoolean()) {
                JsonNode destino = porId.get(enlace.path("targetId").asText());
                if (destino != null) {
                    unidades.addAll(unidadesDe(destino, porId, visitados));
                }
            }
        }
        return unidades;
    }

    private static boolean esUnidad(JsonNode nodo) {
        String tipo = nodo.path("type").asText();
        return tipo.equals("unit") || tipo.equals("model");
    }

    /** El coste puede estar en la unidad o más abajo, en la miniatura o la opción que cuelga de ella. */
    private boolean tienePuntos(JsonNode nodo, Map<String, JsonNode> porId, Set<String> visitados) {
        boolean[] encontrado = {false};
        List<String> enlaces = new ArrayList<>();
        recorrer(nodo, hijo -> {
            for (JsonNode coste : hijo.withArray("costs")) {
                if (PUNTOS.equals(coste.path("typeId").asText()) && coste.path("value").asDouble() > 0) {
                    encontrado[0] = true;
                }
            }
            JsonNode destino = hijo.get("targetId");
            if (destino != null && destino.isTextual()) {
                enlaces.add(destino.asText());
            }
        });
        if (encontrado[0]) {
            return true;
        }
        // Las opciones de la unidad pueden llegar por enlace en vez de estar incrustadas.
        for (String id : enlaces) {
            JsonNode apuntado = porId.get(id);
            if (visitados.add(id) && apuntado != null && tienePuntos(apuntado, porId, visitados)) {
                return true;
            }
        }
        return false;
    }

    private static void indexar(JsonNode nodo, Map<String, JsonNode> porId) {
        recorrer(nodo, hijo -> {
            JsonNode id = hijo.get("id");
            if (id != null && id.isTextual()) {
                porId.putIfAbsent(id.asText(), hijo);
            }
        });
    }

    private static void recorrer(JsonNode nodo, java.util.function.Consumer<JsonNode> visita) {
        if (nodo.isObject()) {
            visita.accept(nodo);
            nodo.fields().forEachRemaining(entrada -> recorrer(entrada.getValue(), visita));
        } else if (nodo.isArray()) {
            nodo.forEach(hijo -> recorrer(hijo, visita));
        }
    }
}
