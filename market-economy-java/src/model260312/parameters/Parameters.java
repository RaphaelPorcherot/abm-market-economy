package model260312.parameters;

import java.util.LinkedList;
import java.util.List;

public abstract class Parameters {

	private final long randomSeed;

	private final int populationSize;

	private final int nSector;

	private final float productivityMax;

	private final float needMax;

	private final int nNeeds;

	private final int nProductions;

	private final float vAMomentumGain;

	private final float vAMomentumBrake;

	private final float vBAgentPriceSensitivity;

	private final float vBAgentMomentumGain;

	private final float vBAgentGamma;

	private final float vBInventorySurvivalRate;

	private final int vBSimulationDuration;

	private final long vBSeed;

	private final float sectorReviewProbability;

	private final float savingPropensity;

	private final int suppliersListNormalSize;

	private final float supplierTurnoverRate;

	public Parameters(long randomSeed, int populationSize, int nSector, int nProductions, float productivityMax,
			int nNeeds, float needMax, float vAmomentumGain, float vAMomentumBrake, int simulationDuration, long vBSeed,
			float sectorReviewProbability, float savingPropensity, int suppliersListNormalSize,
			float supplierTurnoverRate, float vBagentPriceSensitivity, float vBagentGamma,
			float vBAgentMomentumGain, float vBInventorySurvivalRate) {
		this.randomSeed = randomSeed;
		this.populationSize = populationSize;
		this.nSector = nSector;
		this.nProductions = nProductions;
		this.productivityMax = productivityMax;
		this.nNeeds = nNeeds;
		this.needMax = needMax;
		this.vAMomentumGain = vAmomentumGain;
		this.vAMomentumBrake = vAMomentumBrake;
		this.vBSimulationDuration = simulationDuration;
		this.vBSeed = vBSeed;
		this.sectorReviewProbability = sectorReviewProbability;
		this.savingPropensity = savingPropensity;
		this.suppliersListNormalSize = suppliersListNormalSize;
		this.supplierTurnoverRate = supplierTurnoverRate;
		this.vBAgentPriceSensitivity = vBagentPriceSensitivity;
		this.vBAgentGamma = vBagentGamma;
		this.vBAgentMomentumGain = vBAgentMomentumGain;
		this.vBInventorySurvivalRate = vBInventorySurvivalRate;

	}

	public float sectorReviewProbability() {
		return sectorReviewProbability;
	}

	public List<String> getList() {
		var List = new LinkedList<String>();
		List.add("randomSeed," + randomSeed);
		List.add("populationSize," + populationSize);
		List.add("nSector," + nSector);
		List.add("productivityMax," + productivityMax);
		List.add("needMax," + needMax);
		List.add("nNeeds," + nNeeds);
		List.add("nProductions," + nProductions);
		List.add("vAMomentumGain," + vAMomentumGain);
		List.add("vAMomentumBrake," + vAMomentumBrake);
		List.add("vBAgentPriceSensitivity," + vBAgentPriceSensitivity);
		List.add("vBAgentMomentumGain," + vBAgentMomentumGain);
		List.add("vBAgentGamma," + vBAgentGamma);
		List.add("vBInventorySurvivalRate," + vBInventorySurvivalRate);
		List.add("vBSimulationDuration," + vBSimulationDuration);
		List.add("vBSeed," + vBSeed);
		List.add("sectorReviewProbability," + sectorReviewProbability);
		List.add("savingPropensity," + savingPropensity);
		List.add("suppliersListNormalSize," + suppliersListNormalSize);
		List.add("supplierTurnoverRate," + supplierTurnoverRate);
		return List;
	}

	public float needMax() {
		return needMax;
	}

	public int nNeeds() {
		return nNeeds;
	}

	public int nProductions() {
		return nProductions;
	}

	public int nSector() {
		return nSector;
	}

	public long populationRandomSeed() {
		return randomSeed;
	};

	public int populationSize() {
		return populationSize;
	}

	public float productivityMax() {
		return productivityMax;
	}

	public float savingPropensity() {
		return savingPropensity;
	}

	public int suppliersListNormalSize() {
		return suppliersListNormalSize;
	}

	public float supplierTurnoverRate() {
		return supplierTurnoverRate;
	}

	public float vAMomentumBrake() {
		return vAMomentumBrake;
	}

	public float vAMomentumGain() {
		return vAMomentumGain;
	}

	public float vBAgentGamma() {
		return vBAgentGamma;
	}

	public float vBAgentMomentumGain() {
		return vBAgentMomentumGain;
	}

	public float vBAgentPriceSensitivity() {
		return vBAgentPriceSensitivity;
	};

	public long vBSeed() {
		return vBSeed;
	};

	public long vBSimulationDuration() {
		return vBSimulationDuration;
	}

	public float vBInventorySurvivalRate() {
		return vBInventorySurvivalRate;
	};

}