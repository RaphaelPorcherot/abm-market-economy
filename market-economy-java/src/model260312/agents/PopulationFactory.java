package model260312.agents;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

import model260312.parameters.Parameters;

public class PopulationFactory {

	public static List<Agent> create(Parameters parameters) {

		var rng = new Random(parameters.populationRandomSeed());

		var size = parameters.populationSize();

		var nSector = parameters.nSector();

		var productivityMax = new float[nSector];
		for (int i = 0; i < nSector; i++) {
			productivityMax[i] = (1 - rng.nextFloat()) * parameters.productivityMax();
		}

		var needMax = new float[nSector];
		for (var i = 0; i < nSector; i++) {
			needMax[i] = 1+(1 - rng.nextFloat()) * parameters.needMax();
		}

		var nProductions = parameters.nProductions();
		var nNeeds = parameters.nNeeds();

		var agents = new ArrayList<Agent>(size);
		for (var i = 0; i < size; i++) {
			var result = pickTwoDisjointSets(nSector, nProductions, nNeeds, rng);
			var setProductions = result[0];
			var setNeeds = result[1];
			var agent = new Agent(parameters);
			for (var j = 0; j < nProductions; j++) {
				var productionIndex = setProductions[j];
				agent.productivity[productionIndex] = (1 - rng.nextFloat()) * productivityMax[productionIndex];
			}
			for (var j = 0; j < nNeeds; j++) {
				var needIndex = setNeeds[j];
				agent.needs[needIndex] = (1 - rng.nextFloat()) * needMax[needIndex];
			}
			agents.add(i, agent);
			;
		}
		return agents;
	}

	private static int[][] pickTwoDisjointSets(int total, int n, int m, Random rng) {
		if (n + m > total) {
			throw new IllegalArgumentException("n + m > total");
		}

		// Liste des secteurs : 0..total-1
		List<Integer> sectors = new ArrayList<>(total);
		for (int i = 0; i < total; i++) {
			sectors.add(i);
		}

		// Mélange uniforme
		Collections.shuffle(sectors, rng);

		int[] first = new int[n];
		int[] second = new int[m];

		for (int i = 0; i < n; i++) {
			first[i] = sectors.get(i);
		}
		for (int i = 0; i < m; i++) {
			second[i] = sectors.get(n + i);
		}

		return new int[][] { first, second };
	}
}
