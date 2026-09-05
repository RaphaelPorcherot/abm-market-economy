package model260312.models;

import java.util.Arrays;
import java.util.List;

import model260312.agents.Agent;
import model260312.data.MacroData;
import model260312.data.MacroVariable;
import model260312.parameters.Parameters;

public class VersionA extends Model {

	private static float imbalance(float[] demand, float[] supply) {
		float D = 0.0f;
		float S = 0.0f;

		for (int i = 0; i < demand.length; i++) {
			D += Math.abs(demand[i] - supply[i]);
			S += (demand[i] + supply[i]);
		}

		if (S == 0.0)
			return 0.0f;

		return D / S;
	}

	final private int nSector;

	final private float momentumGain;
	final private float momentumBrake;

	final private float[] speed;
	final private float[] prices;
	final private float[] direction;

	// paramètres du critère de stagnation
	final private int historySize = 10; // TODO PARAMETRISER
	final private double tolI = 1e-4; // TODO PARAMETRISER

	// mémoire circulaire des derniers I
	private final float[] I_history = new float[historySize];
	private int I_index = 0;
	private int I_filled = 0;

	public VersionA(Parameters params) {
		super(params);
		this.nSector = params.nSector();
		this.prices = new float[nSector];
		Arrays.fill(prices, 100);
		this.speed = new float[nSector];
		this.direction = new float[nSector];
		this.momentumGain = params.vAMomentumGain();
		this.momentumBrake = params.vAMomentumBrake();
	}

	public void run(List<Agent> population) {

		int iter = 0;
		final int maxIter = 500;

		while (true) {

			if (iter > maxIter) {
				System.out.println("Max iter reached");
				break;
			}

			var macroData = new MacroData(nSector, iter);

			var sectorSize = new int[nSector];
			var totalProductionValue = new float[nSector];
			var totalProductionVolume = new float[nSector];
			var totalConsumptionValue = new float[nSector];

			for (Agent agent : population) {
				Float income = null;
				Integer productionIndex = null;

				for (int i = 0; i < nSector; i++) {
					final float newIncome = agent.productivity(i) * prices[i];
					if (productionIndex == null || newIncome > income) {
						income = newIncome;
						productionIndex = i;
					}
				}

				sectorSize[productionIndex] += 1;
				totalProductionValue[productionIndex] += income;
				totalProductionVolume[productionIndex] += agent.productivity(productionIndex);

				var consumptionValue = agent.consumption(income);
				for (int i = 0; i < nSector; i++) {
					totalConsumptionValue[i] += consumptionValue[i];
				}
			}

			float I = imbalance(totalConsumptionValue, totalProductionValue);

			// enregistrement des données
			for (int i = 0; i < nSector; i++) {
				macroData.setValue(MacroVariable.CONSUMPTION_BUDGET, i, totalConsumptionValue[i]);
				macroData.setValue(MacroVariable.PRODUCTION_VALUE, i, totalProductionValue[i]);
				macroData.setValue(MacroVariable.PRODUCTION_VOLUME, i, totalProductionVolume[i]);
				macroData.setValue(MacroVariable.SECTOR_SIZE, i, sectorSize[i]);
				macroData.setValue(MacroVariable.PRICE, i, prices[i]);
				macroData.setValue(MacroVariable.SPEED, i, speed[i] * direction[i]);
			}
			data.putAll(macroData.getData());

			// affichage succinct pour suivre la convergence
			System.out.printf("%04d  I=%.6f%n", iter, I);

			// critère d'arrêt basé sur la stagnation locale
			if (stagnation(I)) {
				System.out.println("Convergence locale détectée à iter " + iter);
				System.out.println("Final imbalance: " + I);
				break;
			}

			// mise à jour des prix
			for (int i = 0; i < nSector; i++) {
				double excessDemand = totalConsumptionValue[i] - totalProductionValue[i];
				updatePrice(i, excessDemand);
			}

			iter++;

		}
	}

	private boolean stagnation(float I) {
		I_history[I_index] = I;
		I_index = (I_index + 1) % historySize;

		if (I_filled < historySize) {
			I_filled++;
			return false;
		}

		double min = Double.POSITIVE_INFINITY;
		double max = Double.NEGATIVE_INFINITY;

		for (int k = 0; k < historySize; k++) {
			double v = I_history[k];
			if (v < min)
				min = v;
			if (v > max)
				max = v;
		}

		return (max - min) < tolI;
	}

	private void updatePrice(int i, double excessDemand) {
		int newDir;

		if (excessDemand > 0) {
			newDir = +1;
		} else if (excessDemand < 0) {
			newDir = -1;
		} else {
			newDir = 0;
		}

		if (speed[i] == 0) {
			speed[i] = 0.1f;
		}

		if (newDir == direction[i]) {
			speed[i] *= momentumGain;
		} else if (newDir != 0) {
			speed[i] *= momentumBrake;
		}

		direction[i] = newDir;

		double factor = 1 + direction[i] * speed[i];
		if (factor <= 0)
			factor = 1e-9;

		prices[i] *= factor;
	}
}
