package model260312.parameters;

public class ParametersTest0 extends Parameters {

	public ParametersTest0() {

		var randomSeed = 0;
		var populationSize = 10000;
		var nSector = 20;
		var nProductions = 15;
		var productivityMax = 100;
		var nNeeds = 5;
		var needMax = 9;
		var vAMomentumGain = 1.5f;
		var vAMomentumBrake = 0.33f;
		var simulationDuration = 300;
		var bSeed = 0;
		var sectorReviewProbability = 0.05f;
		var savingPropensity = 0.05f;
		var suppliersListNormalSize = 100;
		var supplierTurnoverRate = 0.20f;
		var vBagentPriceSensitivity = .1f; // passer de 0.1 à 0.2 augmente la fréquence des cycles
		var vBAgentGamma = .33f; // 
		var vBAgentMomentumGain = .2f; // Passer à .2 augmente la fréquence des cycles
		var vBInventorySurvivalRate = 1.f; // Passer à 0 supprime les cycles.

		super(randomSeed, populationSize, nSector, nProductions, productivityMax, nNeeds, needMax, vAMomentumGain,
				vAMomentumBrake, simulationDuration, bSeed, sectorReviewProbability, savingPropensity,
				suppliersListNormalSize, supplierTurnoverRate, vBagentPriceSensitivity,
				vBAgentGamma, vBAgentMomentumGain, vBInventorySurvivalRate);

	}

}
