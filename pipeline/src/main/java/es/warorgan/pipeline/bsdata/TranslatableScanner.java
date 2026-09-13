package es.warorgan.pipeline.bsdata;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Localiza los textos traducibles de un fichero de BSData.
 *
 * <p>Trabaja en dos pasadas sobre el mismo contenido: la primera decide sobre el árbol qué valores
 * son traducibles (necesita ver campos hermanos, como el {@code name} de una characteristic), y la
 * segunda recorre el JSON en streaming para anotar el offset exacto de cada literal. Así la
 * reinyección puede sustituir tramos concretos del fichero original en vez de re-serializarlo, que
 * es lo que garantiza que la salida sea idéntica byte a byte salvo en los textos traducidos.
 */
@Component
public class TranslatableScanner {

    /** Characteristics cuyo texto es prosa para el jugador. El resto son estadísticas o keywords. */
    public static final Set<String> PROSE_CHARACTERISTICS = Set.of(
            "Description", "Descriptions", "Capacity", "Effect", "Orders", "Ability", "Button Effect");

    private static final List<String> RULE_ARRAYS = List.of("rules", "sharedRules");

    private final JsonFactory factory = new JsonFactory();
    private final ObjectMapper mapper = new ObjectMapper();

    public JsonNode parse(String raw) {
        try {
            return mapper.readTree(raw);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * @param characteristicTypes id de characteristicType a su nombre, recopilado de todo el dataset:
     *                            un modifier puede escribir sobre un tipo declarado en otro fichero.
     */
    public List<TranslatableText> scan(String file, String raw, Map<String, String> characteristicTypes) {
        Map<String, String> kinds = new LinkedHashMap<>();
        collect(parse(raw), "", kinds, characteristicTypes);

        Map<String, int[]> spans = locateLiterals(raw, kinds.keySet());
        List<TranslatableText> found = new ArrayList<>(kinds.size());
        kinds.forEach((pointer, kind) -> {
            int[] span = spans.get(pointer);
            if (span == null) {
                throw new IllegalStateException("No se localizó el literal de " + pointer + " en " + file);
            }
            found.add(new TranslatableText(file, pointer, kind, decode(raw, span), span[0], span[1]));
        });
        found.sort(Comparator.comparingInt(TranslatableText::literalStart));
        return found;
    }

    private void collect(JsonNode node, String pointer, Map<String, String> out, Map<String, String> types) {
        if (node.isArray()) {
            for (int i = 0; i < node.size(); i++) {
                collect(node.get(i), pointer + "/" + i, out, types);
            }
            return;
        }
        if (!node.isObject()) {
            return;
        }

        JsonNode characteristics = node.get("characteristics");
        if (characteristics != null && characteristics.isArray()) {
            for (int i = 0; i < characteristics.size(); i++) {
                JsonNode characteristic = characteristics.get(i);
                String name = textOf(characteristic, "name");
                if (name != null && PROSE_CHARACTERISTICS.contains(name)
                        && isProse(characteristic.get("$text"))) {
                    out.put(pointer + "/characteristics/" + i + "/$text", "characteristic:" + name);
                }
            }
        }

        for (String arrayName : RULE_ARRAYS) {
            JsonNode rules = node.get(arrayName);
            if (rules != null && rules.isArray()) {
                for (int i = 0; i < rules.size(); i++) {
                    if (isProse(rules.get(i).get("description"))) {
                        out.put(pointer + "/" + arrayName + "/" + i + "/description", "rule");
                    }
                }
            }
        }

        // Un modifier puede sobrescribir el texto de una characteristic: es prosa que el jugador ve.
        JsonNode modifiers = node.get("modifiers");
        if (modifiers != null && modifiers.isArray()) {
            for (int i = 0; i < modifiers.size(); i++) {
                JsonNode modifier = modifiers.get(i);
                String target = types.get(textOf(modifier, "field"));
                if (target != null && PROSE_CHARACTERISTICS.contains(target)
                        && isProse(modifier.get("value"))) {
                    out.put(pointer + "/modifiers/" + i + "/value", "modifier:" + target);
                }
            }
        }

        node.fields().forEachRemaining(entry ->
                collect(entry.getValue(), pointer + "/" + escape(entry.getKey()), out, types));
    }

    private Map<String, int[]> locateLiterals(String raw, Set<String> wanted) {
        Map<String, int[]> spans = new HashMap<>();
        if (wanted.isEmpty()) {
            return spans;
        }
        try (JsonParser parser = factory.createParser(raw)) {
            List<String> segments = new ArrayList<>();
            Deque<Frame> stack = new ArrayDeque<>();
            String pendingField = null;
            JsonToken token;
            while ((token = parser.nextToken()) != null) {
                if (token == JsonToken.FIELD_NAME) {
                    pendingField = parser.currentName();
                    continue;
                }
                Frame top = stack.peek();
                String segment = top == null ? null
                        : (top.array ? Integer.toString(top.index++) : escape(pendingField));
                switch (token) {
                    case START_OBJECT, START_ARRAY -> {
                        if (segment != null) {
                            segments.add(segment);
                        }
                        stack.push(new Frame(token == JsonToken.START_ARRAY, segment != null));
                    }
                    case END_OBJECT, END_ARRAY -> {
                        if (stack.pop().contributesSegment) {
                            segments.remove(segments.size() - 1);
                        }
                    }
                    case VALUE_STRING -> {
                        String pointer = pointerOf(segments, segment);
                        if (wanted.contains(pointer)) {
                            spans.put(pointer, literalSpan(raw, parser, pointer));
                        }
                    }
                    default -> {
                    }
                }
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return spans;
    }

    /** Devuelve {inicio de la comilla de apertura, siguiente a la de cierre} del literal actual. */
    private int[] literalSpan(String raw, JsonParser parser, String pointer) throws IOException {
        int start = (int) parser.currentTokenLocation().getCharOffset();
        while (start < raw.length() && raw.charAt(start) != '"') {
            start++;
        }
        int i = start + 1;
        while (i < raw.length()) {
            char c = raw.charAt(i);
            if (c == '\\') {
                i += 2;
                continue;
            }
            if (c == '"') {
                break;
            }
            i++;
        }
        int[] span = {start, i + 1};
        // El offset viene del parser: si el tramo no reproduce el valor, hay un desfase y la
        // reinyección corrompería el fichero. Mejor romper aquí que escribir JSON inválido.
        if (!decode(raw, span).equals(parser.getText())) {
            throw new IllegalStateException("Offset incoherente para " + pointer);
        }
        return span;
    }

    private String decode(String raw, int[] span) {
        try {
            return mapper.readValue(raw.substring(span[0], span[1]), String.class);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static String pointerOf(List<String> segments, String last) {
        StringBuilder sb = new StringBuilder();
        for (String segment : segments) {
            sb.append('/').append(segment);
        }
        return sb.append('/').append(last).toString();
    }

    private static String escape(String segment) {
        return segment == null ? null : segment.replace("~", "~0").replace("/", "~1");
    }

    private static String textOf(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value != null && value.isTextual() ? value.asText() : null;
    }

    private static boolean isProse(JsonNode node) {
        return node != null && node.isTextual() && !node.asText().isBlank();
    }

    private static final class Frame {
        private final boolean array;
        private final boolean contributesSegment;
        private int index;

        private Frame(boolean array, boolean contributesSegment) {
            this.array = array;
            this.contributesSegment = contributesSegment;
        }
    }
}
