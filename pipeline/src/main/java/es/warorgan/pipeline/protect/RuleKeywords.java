package es.warorgan.pipeline.protect;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Las palabras clave entre corchetes ({@code [SUSTAINED HITS 2]}, {@code [PISTOL]}). */
public final class RuleKeywords {

    private static final Pattern BRACKETED = Pattern.compile("\\[[^\\[\\]\\n]{1,80}]");

    private RuleKeywords() {
    }

    public static Set<String> in(String text) {
        Set<String> keywords = new LinkedHashSet<>();
        Matcher matcher = BRACKETED.matcher(text);
        while (matcher.find()) {
            keywords.add(matcher.group());
        }
        return keywords;
    }
}
