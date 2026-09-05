package model260312.experiments;

import java.awt.Toolkit;
import java.io.File;
import java.io.IOException;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

import model260312.agents.PopulationFactory;
import model260312.data.MacroDataCsvExporter;
import model260312.models.VersionB;
import model260312.parameters.Parameters;
import model260312.parameters.ParametersCsvExporter;

public class ExperimentB extends Experiment {

	public ExperimentB(Parameters params) {
		super(params);
	}

	@Override
	public void run() {
		final String start = DateTimeFormatter.ofPattern("YYMMddHHmmss").withZone(ZoneId.systemDefault())
				.format(Instant.ofEpochMilli(Instant.now().toEpochMilli()));
		System.out.print("Running ExperimentB: ");
		System.out.println(this.getClass().getName() + "-" + start);

		var population = PopulationFactory.create(params);
		var modelB = new VersionB(params);
		modelB.run(population);
		var fileKey = start + "modelB";
		var data = modelB.getData();
		try {
			MacroDataCsvExporter.export(data, "output/" + fileKey + ".output.csv");
			ParametersCsvExporter.export(params, "output/" + fileKey + ".parameters.csv");
		} catch (IOException e) {
			System.err.print("Something went wrong.");
			e.printStackTrace();
		}

		File report = renderReport(fileKey, "rmd/analyseB.Rmd");
		if (report != null && report.exists()) {
			openHtmlReport(report);
		} else {
		    System.err.println("Rapport non ouvert.");
		}
		Toolkit.getDefaultToolkit().beep();
		System.out.print("ExperimentB successfuly completed.");
	}

}