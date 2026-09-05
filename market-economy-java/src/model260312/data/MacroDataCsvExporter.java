package model260312.data;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.Map;

public final class MacroDataCsvExporter {

    private static final String HEADER = "t,sector,dataType,value";

    private MacroDataCsvExporter() {
        // utilitaire, pas d'instance
    }

    public static void export(
            Map<MacroKey, Float> data,
            String filePath
    ) throws IOException {

        try (BufferedWriter writer = Files.newBufferedWriter(Path.of(filePath))) {

            writer.write(HEADER);
            writer.newLine();

            // Tri stable : période → secteur → variable
            data.entrySet().stream()
                    .sorted(Comparator.comparingInt((Map.Entry<MacroKey, Float> e) -> e.getKey().period())
                            .thenComparingInt(e -> e.getKey().sector())
                            .thenComparing(e -> e.getKey().variable().name()))
                    .forEach(entry -> {
                        try {
                        	
                            writer.write(toCsvLine(entry.getKey(), entry.getValue()));
                            writer.newLine();
                        } catch (IOException ex) {
                            throw new RuntimeException(ex);
                        }
                    });
        }
    }

    private static String toCsvLine(MacroKey key, Float value) {
    	String sValue = (value != null) ? value.toString() : "NA";
        return key.period()
                + "," + key.sector()
                + "," + key.variable().csvName()
                + "," + sValue;
    }
}