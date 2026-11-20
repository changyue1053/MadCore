import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import javax.tools.ToolProvider;
import org.jetbrains.kotlin.abi.tools.AbiFilters;
import org.jetbrains.kotlin.abi.tools.AbiTools;

/** Smoke the real JDK and the same analyzer before comparing production AARs. */
public final class PackagedAarAbiWithControls {
    private static File compileFixture(Path work, String side, String returnType, int value) throws Exception {
        Path directory = Files.createDirectory(work.resolve(side));
        Path source = directory.resolve("Control.java");
        String text = """
                package control;
                public class Control {
                    public %s exposed() { return hidden(); }
                    protected String inherited() { return "fixture"; }
                    private int hidden() { return %d; }
                }
                """.formatted(returnType, value);
        Files.writeString(source, text, StandardCharsets.UTF_8);
        var compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null || compiler.run(null, null, null, "--release", "21", "-d",
                directory.toString(), source.toString()) != 0) {
            throw new IllegalStateException("JDK 21 control compilation failed");
        }
        Path archive = directory.resolve("control.jar");
        try (var jar = new JarOutputStream(Files.newOutputStream(archive))) {
            jar.putNextEntry(new JarEntry("control/Control.class"));
            Files.copy(directory.resolve("control/Control.class"), jar);
            jar.closeEntry();
        }
        return archive.toFile();
    }

    private static String dump(AbiTools analyzer, File artifact) {
        var text = new StringBuilder();
        analyzer.printJvmDump(text, List.of(artifact), AbiFilters.Companion.getEMPTY());
        return text.toString();
    }

    public static void main(String[] args) throws Exception {
        Path output = Path.of(System.getenv("MADCORE_AAR_ABI_OUTPUT"));
        Path control = Files.createDirectory(output.getParent().resolve("compiler-control"));
        AbiTools analyzer = AbiTools.Companion.getInstance(PackagedAarAbiWithControls.class.getClassLoader());
        String baseline = dump(analyzer, compileFixture(control, "baseline", "int", 1));
        String bodyOnly = dump(analyzer, compileFixture(control, "body-only", "int", 2));
        String descriptor = dump(analyzer, compileFixture(control, "descriptor", "long", 2));
        long bodyChange = Files.mismatch(control.resolve("baseline/control/Control.class"),
                                        control.resolve("body-only/control/Control.class"));
        if (bodyChange < 0 || !baseline.contains("public fun exposed ()I")
                || !baseline.contains("protected fun inherited ()Ljava/lang/String;")
                || baseline.contains("hidden")
                || !baseline.equals(bodyOnly)
                || baseline.equals(descriptor)
                || !descriptor.contains("public fun exposed ()J")
                || descriptor.contains("public fun exposed ()I")) {
            throw new IllegalStateException("Packaged ABI analyzer compiler control failed");
        }
        PackagedAarAbi.main(args);
    }
}
