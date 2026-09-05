package model260312.parameters;

import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.util.LinkedList;
import java.util.List;

public class ParametersCsvExporter {

	private static final String HEADER = "parameter,value";

	static private void writeDataToCSV(List<String> data, String fileName) throws IOException {
		try (BufferedWriter writer = new BufferedWriter(new FileWriter(fileName, true))) {
			for (String line : data) {
				writer.write(line);
				writer.newLine();
			}
		}
	}

	public static void export(Parameters params, String name) {
		var list = new LinkedList<String>();
		list.add(HEADER);
		list.addAll(params.getList());
		try {
			String fileName = name;
			writeDataToCSV(list, fileName);
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

}
