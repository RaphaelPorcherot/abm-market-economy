package model260312;

import model260312.experiments.Experiment;
import model260312.experiments.ExperimentB;
import model260312.parameters.ParametersTest0;

public class MainB {

	private static Experiment exp = new ExperimentB(new ParametersTest0());

	public static void main(String[] args) {
		exp.run();
	}
}
