package model260312.experiments;

import java.awt.Desktop;
import java.io.File;
import java.io.IOException;
import java.util.Random;

import model260312.parameters.Parameters;

public abstract class Experiment {

	static private String findRscript() {

		String[] candidates = { "/usr/local/bin/Rscript", // macOS Intel
				"/opt/homebrew/bin/Rscript", // macOS Apple Silicon
				"/usr/bin/Rscript", // Linux
				"Rscript" // PATH
		};

		for (String path : candidates) {
			File f = new File(path);
			if (f.exists() && f.canExecute())
				return f.getAbsolutePath();
		}

		return null;
	}

	protected static void openHtmlReport(File htmlFile) {
		try {
			if (!htmlFile.exists()) {
				throw new IllegalArgumentException("Fichier HTML introuvable : " + htmlFile.getAbsolutePath());
			}

			Desktop desktop = Desktop.getDesktop();
			desktop.browse(htmlFile.toURI());

		} catch (IOException e) {
			throw new RuntimeException("Impossible d’ouvrir le rapport HTML", e);
		}
	}

	static protected File renderReport(String fileKey, String rmdFile) {

		File projectDir = new File(System.getProperty("user.dir"));
		File outputDir = new File(projectDir, "output");
		if (!outputDir.exists())
			outputDir.mkdirs();

		File rmd = new File(projectDir, rmdFile);
		File outputHtml = new File(outputDir, fileKey + ".rapport.html");

		String rscript = findRscript();
		if (rscript == null) {
			System.err.println("Erreur : Rscript introuvable.");
			return null;
		}

		// Commande R : render avec param project_dir pour chemins absolus
		
		String rCommand = "rmarkdown::render(" + "input=normalizePath('" + rmd.getAbsolutePath() + "'),"
				+ "output_file='" + fileKey + ".rapport.html'," + "output_dir=normalizePath('"
				+ outputDir.getAbsolutePath() + "')," + "params=list(" + "file_key='" + fileKey + "',"
				+ "project_dir=normalizePath('" + projectDir.getAbsolutePath() + "')" + ")," + "quiet=TRUE)";

		ProcessBuilder pb = new ProcessBuilder(rscript, "-e", rCommand);
		pb.directory(projectDir);
		pb.inheritIO();

		// PATH pour que R et Pandoc soient trouvés sur macOS/Linux
		pb.environment().put("PATH", "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin");

		try {
			Process p = pb.start();
			int exitCode = p.waitFor();

			if (exitCode != 0) {
				System.err.println("Erreur : échec du rendu RMarkdown (code " + exitCode + ")");
				return null;
			}

			if (!outputHtml.exists()) {
				System.err.println("Erreur : rapport HTML non généré : " + outputHtml.getAbsolutePath());
				return null;
			}

			return outputHtml;

		} catch (IOException | InterruptedException e) {
			System.err.println("Erreur lors du rendu du rapport : " + e.getMessage());
			if (e instanceof InterruptedException)
				Thread.currentThread().interrupt();
			return null;
		}
	}

	protected final Parameters params;

	protected final Random rng;

	public Experiment(Parameters params) {
		this.params = params;
		this.rng = new Random();
	}

	public abstract void run();

}
