package model260312;

import model260312.experiments.Experiment;
import model260312.experiments.ExperimentBA;
import model260312.parameters.ParametersTest0;

public class MainBA {

	private static Experiment exp = new ExperimentBA(new ParametersTest0());

	public static void main(String[] args) {
		exp.run();
	}
}
