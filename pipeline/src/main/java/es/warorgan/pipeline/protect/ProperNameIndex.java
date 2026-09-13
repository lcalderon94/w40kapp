package es.warorgan.pipeline.protect;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Detecta qué nombres propios del dataset aparecen dentro de un texto, para poder avisar al
 * traductor de que deben quedarse en inglés tal cual.
 *
 * <p>Busca anclando en principio de palabra y comparando distinguiendo mayúsculas: los nombres del
 * juego siempre van capitalizados, así que "Blast" como nombre de regla se detecta y "blast" como
 * palabra corriente no. En cada posición gana el nombre más largo, de modo que dentro de
 * "Chaos Lord" no se reporta además "Chaos".
 */
public class ProperNameIndex {

    private static final int MIN_LENGTH = 3;

    private final Map<String, List<String>> byFirstWord;

    public ProperNameIndex(Collection<String> names) {
        Map<String, List<String>> index = new HashMap<>();
        for (String name : names) {
            String trimmed = name.trim();
            if (trimmed.length() < MIN_LENGTH || !hasUpperCase(trimmed)) {
                continue;
            }
            String firstWord = firstWordAt(trimmed, 0);
            if (firstWord.isEmpty()) {
                continue;
            }
            index.computeIfAbsent(firstWord.toLowerCase(), key -> new ArrayList<>()).add(trimmed);
        }
        index.values().forEach(list -> list.sort(Comparator.comparingInt(String::length).reversed()));
        this.byFirstWord = index;
    }

    public Set<String> matchesIn(String text) {
        Set<String> found = new LinkedHashSet<>();
        int position = 0;
        while (position < text.length()) {
            if (!isWordStart(text, position)) {
                position++;
                continue;
            }
            String word = firstWordAt(text, position);
            if (word.isEmpty()) {
                position++;
                continue;
            }
            for (String candidate : byFirstWord.getOrDefault(word.toLowerCase(), List.of())) {
                if (text.startsWith(candidate, position) && endsOnBoundary(text, position + candidate.length())) {
                    found.add(candidate);
                    break;
                }
            }
            position += word.length();
        }
        return found;
    }

    private static boolean isWordStart(String text, int position) {
        return Character.isLetterOrDigit(text.charAt(position))
                && (position == 0 || !Character.isLetterOrDigit(text.charAt(position - 1)));
    }

    private static boolean endsOnBoundary(String text, int end) {
        return end >= text.length() || !Character.isLetterOrDigit(text.charAt(end));
    }

    private static String firstWordAt(String text, int from) {
        int end = from;
        while (end < text.length() && Character.isLetterOrDigit(text.charAt(end))) {
            end++;
        }
        return text.substring(from, end);
    }

    private static boolean hasUpperCase(String value) {
        return value.chars().anyMatch(Character::isUpperCase);
    }
}
