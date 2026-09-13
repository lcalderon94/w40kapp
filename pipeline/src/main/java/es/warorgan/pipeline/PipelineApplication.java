package es.warorgan.pipeline;

import es.warorgan.pipeline.cli.ApplyCommand;
import es.warorgan.pipeline.cli.ExtractCommand;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

@SpringBootApplication
@EnableConfigurationProperties(PipelineProperties.class)
public class PipelineApplication implements ApplicationRunner {

    private final ExtractCommand extract;
    private final ApplyCommand apply;

    public PipelineApplication(ExtractCommand extract, ApplyCommand apply) {
        this.extract = extract;
        this.apply = apply;
    }

    public static void main(String[] args) {
        // El informe sale en español y la consola por defecto no siempre es UTF-8 (Windows).
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8));
        SpringApplication.run(PipelineApplication.class, args);
    }

    @Override
    public void run(ApplicationArguments args) {
        List<String> commands = args.getNonOptionArgs();
        String command = commands.isEmpty() ? "" : commands.get(0);
        switch (command) {
            case "extract" -> extract.run();
            case "apply" -> apply.run();
            default -> throw new IllegalArgumentException(
                    "Uso: extract | apply (recibido: '" + command + "')");
        }
    }
}
