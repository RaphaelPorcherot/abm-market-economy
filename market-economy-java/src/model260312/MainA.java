package model260312;

import model260312.experiments.Experiment;
import model260312.experiments.ExperimentA;
import model260312.parameters.ParametersTest0;

public class MainA {

	private static Experiment exp = new ExperimentA(new ParametersTest0());

	public static void main(String[] args) {
		exp.run();
	}
}
