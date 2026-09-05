package model260312.models;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Random;

import model260312.agents.Agent;
import model260312.agents.World;
import model260312.data.MacroData;
import model260312.parameters.Parameters;

public class VersionB extends Model implements World {

	private final long simulationDuration;

	private Long simulationStartMillis;

	private Long iterationStart;

	private int currentPeriod;

	private final Random random;

	private List<Agent> population;

	public VersionB(Parameters params) {
		super(params);
		this.simulationDuration = params.vBSimulationDuration();
		this.random = new Random(params.vBSeed());
	}

	private void chrono() {

		var now = Instant.now().toEpochMilli();

		if (simulationStartMillis == null) {
			simulationStartMillis = now;
		} else {

			var elapsed = now - simulationStartMillis;
			var meanIterationDuration = elapsed / currentPeriod;
			var remainingIterations = (long) (simulationDuration - currentPeriod);
			var remainingTime = remainingIterations * meanIterationDuration;

			var expectedEnd = DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault())
					.format(Instant.ofEpochMilli(now + remainingTime));

			System.out.println("Period " + (currentPeriod - 1) + ", duration " + (now - iterationStart)
					+ " ms, expected end of the simulation around " + expectedEnd + ".");
		}
		iterationStart = now;

	}

	@Override
	public int getNumberOfAgents() {
		return population.size();
	}

	@Override
	public Agent pickRandomAgent() {
		return population.get(random.nextInt(population.size()));
	}

	public List<Agent> pickRandomAgents(int k) {
		var n = population.size();
		if (k > n)
			throw new IllegalArgumentException("k > size");

		// Pour éviter les collisions, on utilise un petit set d'indices tirés
		// Comme k <= 100, le coût est minuscule.
		var indices = new HashSet<Integer>(k * 2);

		while (indices.size() < k)
			indices.add(random.nextInt(n));

		var result = new ArrayList<Agent>(k);
		for (var idx : indices)
			result.add(population.get(idx));

		return result;
	}

	@Override
	public Random random() {
		return random;
	}

	@Override
	public void run(List<Agent> population) {

		this.population = population;

		for (Agent agent : population) {
			agent.setWorld(this);
		}

		for (currentPeriod = 0; currentPeriod < simulationDuration; currentPeriod++) {

			chrono();

			var macroData = new MacroData(nSector, currentPeriod);

			Collections.shuffle(population, this.random);

			for (Agent agent : population) {
				agent.setMacroData(macroData);
				agent.preMarketActions();
			}

			for (Agent agent : population) {
				agent.marketActions();
			}

			for (Agent agent : population) {
				agent.postMarketActions();
			}

			testRespectRicardo();

			data.putAll(macroData.getData());

		}
	}

	private void testRespectRicardo() {
		var rNull = 0f;
		var rPositif = 0f;
		var rNegatif = 0f;
		for (int i = 1; i < 100000; i++) {
			var a = random.nextInt(population.size());
			var b = random.nextInt(population.size());
			if (a != b) {
				var agentA = population.get(a);
				var agentB = population.get(b);
				Boolean isRicardian = this.respectsRicardo(agentA, agentB);
				if (isRicardian == null) {
					rNull++;
				} else if (isRicardian) {
					rPositif++;
				} else {
					rNegatif++;
				}
			}
		}
		var ratio = rPositif / (rNull + rPositif + rNegatif);
		System.out.println(ratio);
	}
}
