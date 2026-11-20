import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.jetbrains.kotlin.abi.tools.AbiFilters;
import org.jetbrains.kotlin.abi.tools.AbiTools;

public final class PackagedAarAbi {
    public static void main(String[] args) throws Exception {
        Path input = Path.of(System.getenv("MADCORE_AAR_ABI_INPUT"));
        Path output = Path.of(System.getenv("MADCORE_AAR_ABI_OUTPUT"));
        AbiTools analyzer = AbiTools.Companion.getInstance(PackagedAarAbi.class.getClassLoader());
        List<String> modules = Files.readAllLines(input.resolve("modules.txt"), StandardCharsets.US_ASCII);
        for (String side : List.of("baseline", "candidate")) {
            Path target = Files.createDirectories(output.resolve(side));
            for (String module : modules) {
                try (var files = Files.list(input.resolve(side).resolve(module));
                     var report = Files.newBufferedWriter(target.resolve(module + ".api"), StandardCharsets.UTF_8)) {
                    List<File> jars = files.filter(Files::isRegularFile)
                        .filter(path -> path.getFileName().toString().endsWith(".jar"))
                        .sorted().map(Path::toFile).toList();
                    if (jars.isEmpty()) {
                        throw new IllegalStateException("No validated input JARs");
                    }
                    analyzer.printJvmDump(report, jars, AbiFilters.Companion.getEMPTY());
                }
            }
        }
    }
}
