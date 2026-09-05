package model260312.experiments;

import java.awt.Toolkit;
import java.io.File;
import java.io.IOException;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

import model260312.agents.PopulationFactory;
import model260312.data.MacroDataCsvExporter;
import model260312.models.VersionA;
import model260312.parameters.Parameters;
import model260312.parameters.ParametersCsvExporter;

public class ExperimentA extends Experiment {

	public ExperimentA(Parameters params) {
		super(params);
	}

	@Override
	public void run() {
		final String start = DateTimeFormatter.ofPattern("YYMMddHHmmss").withZone(ZoneId.systemDefault())
				.format(Instant.ofEpochMilli(Instant.now().toEpochMilli()));
		System.out.println(this.getClass().getName() + "-" + start);

		var population = PopulationFactory.create(params);
		var modelA = new VersionA(params);
		modelA.run(population);
		var fileKey = start + "modelA";
		var data = modelA.getData();
		try {
			MacroDataCsvExporter.export(data, "output/" + fileKey + ".output.csv");
			ParametersCsvExporter.export(params, "output/" + fileKey + ".parameters.csv");
		} catch (IOException e) {
			System.err.print("Something went wrong.");
			e.printStackTrace();
		}

		File report = renderReport(fileKey, "analyseA.Rmd");
		if (report != null && report.exists()) {
			openHtmlReport(report);
		} else {
		    System.err.println("Rapport non ouvert.");
		}
		Toolkit.getDefaultToolkit().beep();
	}

}