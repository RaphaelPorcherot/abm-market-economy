package model260312.agents;

import java.util.LinkedHashSet;
import java.util.LinkedList;
import java.util.Set;

import model260312.data.MacroData;
import model260312.data.MacroVariable;
import model260312.parameters.Parameters;

public class Agent {

	// Paramètres de l'agent

	final private int numberOfGoods;
	final float[] needs;
	final float[] productivity;
	final private float sectorReviewProbability;
	final private float savingPropensity;
	final private int suppliersListNormalSize;
	final private int numSuppliersToReject;

	// Variables d'état

	private World world;
	private Integer productionIndex;
	final private float[] inventory;
	private float[] consumptionBudget;
	private float money;
	private float price;
	private float expectedIncome;
	/**
	 * État qui accumule l’effet des étapes successives et la direction de la
	 * recherche du prix.
	 */
	private double priceMomentum = 0;

	private MacroData macroData;

	private LinkedList<Agent> suppliers = new LinkedList<Agent>();
	/**
	 * momentumGain = alpha = renforcement systématique
	 */
	private final float momentumGain;

	/**
	 * priceSensitivity = beta = coefficient multiplicatif pour le prix
	 */
	private final float priceSensitivity;

	/**
	 * Coup de frein en cas de changement de direction
	 */
	private final float gamma;

	private final float inventorySurvivalRate;

	public Agent(Parameters params) {
		numberOfGoods = params.nSector();
		needs = new float[numberOfGoods];
		productivity = new float[numberOfGoods];
		sectorReviewProbability = params.sectorReviewProbability();
		savingPropensity = params.savingPropensity();
		suppliersListNormalSize = params.suppliersListNormalSize();
		inventory = new float[numberOfGoods];
		numSuppliersToReject = (int) (suppliersListNormalSize * params.supplierTurnoverRate());
		priceSensitivity = params.vBAgentPriceSensitivity();
		gamma = params.vBAgentGamma();
		momentumGain = params.vBAgentMomentumGain();
		inventorySurvivalRate = params.vBInventorySurvivalRate();
	}

	/**
	 * @return
	 */
	private boolean allBudgetsCompleted() {

		for (var index = 0; index < numberOfGoods; index++) {
			if (consumptionBudget[index] > 0) {
				return false;
			}
		}
		return true;
	}

	private boolean allSupplierExhausted() {
		// Si tous les suppliers pour lesquels nous avons du budget sont vides, exit
		for (Agent currentSupplier : suppliers) {

			var index = currentSupplier.productionIndex;

			if (currentSupplier.inventory[index] > 0 && consumptionBudget[index] > 0) {

				return false;

			}
		}
		return true;
	}

	private void calculateConsumptionBudget() {
		var saving = expectedIncome * savingPropensity;
		var consumptionBudgetTotalAmount = Math.max(0, money + expectedIncome - saving);
		if (consumptionBudgetTotalAmount < 0) {
			throw new RuntimeException("consumptionBudgetTotalAmount should not be negative.");
		}
		consumptionBudget = consumption(consumptionBudgetTotalAmount);
		for (var index = 0; index < numberOfGoods; index++) {
			macroData.addValue(MacroVariable.CONSUMPTION_BUDGET, index, consumptionBudget[index]);
		}
	}

	/**
	 * @param income
	 * @return
	 */
	public float[] consumption(float income) {
		var expenses = new float[needs.length];

		var sum = 0.0f;
		for (var w : needs) {
			sum += w;
		}
		if (sum == 0.0) {
			return expenses; // aucun besoin déclaré → aucune dépense
		}

		for (var i = 0; i < needs.length; i++) {
			expenses[i] = income * (needs[i] / sum);
		}

		return expenses;
	}

	/**
	 * 
	 */
	public void marketActions() {

		searchNewSuppliers();

		var activeSuppliers = performMarketTransactions();

		updateSuppliersList(activeSuppliers);

	}

	/**
	 * @return
	 */
	private Set<Agent> performMarketTransactions() {

		var activeSuppliers = new LinkedHashSet<Agent>();

		while (true) {

			if (allBudgetsCompleted())
				break;

			if (allSupplierExhausted())
				break;

			var bestSuppliers = selectBestSuppliers();

			for (var index = 0; index < numberOfGoods; index++) {

				if (consumptionBudget[index] > 0 && bestSuppliers[index] != null) {

					var supplier = bestSuppliers[index];

					var offerTotalValue = supplier.inventory[index] * supplier.price;
					var transactionValue = Math.min(offerTotalValue, consumptionBudget[index]);
					var transactionVolume = Math.min(supplier.inventory[index], transactionValue / supplier.price);

					money -= transactionValue;
					supplier.money += transactionValue;

					consumptionBudget[index] -= transactionValue;
					supplier.inventory[index] -= transactionVolume;

					activeSuppliers.add(supplier);
					suppliers.remove(supplier);

					// Stats

					macroData.addValue(MacroVariable.CONSUMPTION_VALUE, index, transactionValue);
					macroData.addValue(MacroVariable.CONSUMPTION_VOLUME, index, transactionVolume);
					macroData.addValue(MacroVariable.LABOR_USED, index,
							transactionVolume / supplier.productivity[index]);

					// Il serait peut-être utile de compter le nombre de transactions.
				}
			}
		}

		return activeSuppliers;
	}

	/**
	 * 
	 */
	public void postMarketActions() {
		updateProductionPrice();
	}

	/**
	 * 
	 */
	public void preMarketActions() {
		selectProduction();
		production();
		calculateConsumptionBudget();
	}

	public void print() {
		for (int i = 0; i < needs.length; i++) {
			if (needs[i] != 0) {
				System.out.println("Need " + i + ": " + needs[i]);
			}
		}
		for (int i = 0; i < productivity.length; i++) {
			if (productivity[i] != 0) {
				System.out.println("Productivity " + i + ": " + productivity[i]);
			}
		}
	}

	private void production() {
		var productionVolume = productivity(productionIndex);
		inventory[productionIndex] += productionVolume;
		macroData.addValue(MacroVariable.PRODUCTION_VOLUME, productionIndex, productionVolume);
		macroData.addValue(MacroVariable.PRODUCTION_VALUE, productionIndex, productionVolume * price);
		macroData.addValue(MacroVariable.SECTOR_SIZE, productionIndex, 1);
	}

	public int productionIndex() {
		return productionIndex;
	}

	public float productivity() {
		return productivity[productionIndex];
	}

	public float productivity(int i) {
		return productivity[i];
	}

	/**
	 * 
	 */
	private void searchNewSuppliers() {

		int missing = suppliersListNormalSize - suppliers.size();

		if (suppliers.size() >= suppliersListNormalSize)
			throw new IllegalArgumentException();

		if (suppliersListNormalSize > world.getNumberOfAgents() - 1) {
			throw new IllegalArgumentException("Supplier list size exceeds available population.");
		}

		int attempts = 0;
		int maxAttempts = missing * 20; // marge large

		while (suppliers.size() < suppliersListNormalSize) {

			if (attempts++ > maxAttempts) {
				throw new IllegalStateException("Too many duplicate draws while filling supplier list.");
			}

			var candidate = world.pickRandomAgent();

			if (candidate != this && !suppliers.contains(candidate)) {
				suppliers.add(candidate);
			}
		}

		if (suppliers.size() != suppliersListNormalSize) {
			System.err.println(suppliers.size() + ", " + suppliersListNormalSize);
			throw new IllegalStateException("Supplier list size is not equal to L.");
		}

	}

	/**
	 * @return
	 */
	private Agent[] selectBestSuppliers() {

		var bestSuppliers = new Agent[numberOfGoods];

		for (Agent currentSupplier : suppliers) {

			var index = currentSupplier.productionIndex;

			if (currentSupplier.inventory[index] > 0 && consumptionBudget[index] > 0) {

				if (bestSuppliers[index] == null || currentSupplier.price < bestSuppliers[index].price) {
					bestSuppliers[index] = currentSupplier;
				}
			}
		}

		return bestSuppliers;
	}

	/**
	 * 
	 */
	private void selectProduction() {

		if (productionIndex == null) {
			// Initialisation du prix : un au aléatoire, compris entre 0 exclu et 200
			// inclus.
			// TODO Il faut paramétriser cet intervalle.
			while (true) {
				productionIndex = world.random().nextInt(numberOfGoods);
				if (productivity() > 0) {
					price = 200 - world.random().nextFloat(200); // TODO should be a parameter
					expectedIncome = price * productivity();
					break;
				}
			}
		} else {

			if (inventorySurvivalRate < 1) {
				// Cas d'une marchandise partiellement ou totalement périssable.
				// Alors destruction d'une part des stocks antérieurs
				// TODO C'est un peu un cheveu sur la soupe : qu'est-ce que l'érosion des
				// stocks vient faire dans une méthode censée déterminer la production future ?
				var before = inventory[this.productionIndex];
				inventory[this.productionIndex] = inventorySurvivalRate * inventory[this.productionIndex];
				var product_destruction = before - inventory[this.productionIndex];
				macroData.addValue(MacroVariable.PRODUCT_DESTRUCTION, productionIndex, product_destruction);
				// TODO Vérifier la cohérence stock-flux après cette étape
			}

			if (world.random().nextDouble() < sectorReviewProbability) {
				
				// On arrive enfin à la sélection du secteur de production, proprement dite.
				
				expectedIncome = price * productivity();
				
				for (var iter = 0; iter < 10; iter++) {
					
					// TODO 10 should be a parameter
					// TODO Problème : les petits secteurs seront très rarement imités.
					
					var randomAgent = world.pickRandomAgent();
					var newProductionIndex = randomAgent.productionIndex;
					if (newProductionIndex != productionIndex) {
						var newPrice = randomAgent.price;
						var newIncome = newPrice * productivity(newProductionIndex);
						if (newIncome > expectedIncome) {
							
							// Changement de production
							
							// Stats
							macroData.addValue(MacroVariable.PRODUCT_DESTRUCTION, productionIndex,
									inventory[productionIndex]);
							// TODO Il pourrait être intéressant de compter et enregistrer le nombre de changements de secteur
							
							
							// Imitation
							inventory[this.productionIndex] = 0;
							productionIndex = newProductionIndex;
							expectedIncome = newIncome;
							price = newPrice;
							priceMomentum = 0;
							
							break;
						}
					}
				}
			}
		}
	}

	public void setMacroData(MacroData macroData) {
		this.macroData = macroData;
	}

	public void setWorld(World world) {
		this.world = world;
	}

	/**
	 * 
	 */
	private void updateProductionPrice() {

		int direction;

		if (inventory[productionIndex] > 0) {
			direction = -1;
			macroData.addValue(MacroVariable.UNSOLD_VOLUME, productionIndex, inventory[productionIndex]);
			macroData.addValue(MacroVariable.UNSOLD_VOLUME_POSITIF, productionIndex, 1);
		} else {
			direction = +1;
			macroData.addValue(MacroVariable.UNSOLD_VOLUME_POSITIF, productionIndex, 0);
			macroData.addValue(MacroVariable.UNSOLD_VOLUME, productionIndex, 0);
		}

		double amplitude = Math.abs(priceMomentum);

		boolean reversal = (priceMomentum != 0.0) && (Math.signum(priceMomentum) != direction);

		if (reversal) {
			// freinage au retournement
			amplitude *= gamma; // 0 < gamma < 1
		} else {
			// accélération
			amplitude += momentumGain; // α
		}

		// éviter amplitude négative si gros choc négatif
		amplitude = Math.max(0.0, amplitude);

		priceMomentum = direction * amplitude;

		price *= Math.exp(priceSensitivity * priceMomentum);

		macroData.addValue(MacroVariable.MAX_PRICE, productionIndex, price);
		macroData.addValue(MacroVariable.MIN_PRICE, productionIndex, price);
	}

	/**
	 * @param activeSuppliers
	 */
	private void updateSuppliersList(Set<Agent> activeSuppliers) {

		var reordered = new LinkedList<>(activeSuppliers);
		reordered.addAll(suppliers);
		
		// FIXME : Il me semble que cette méthode ne fait rien de reordered. Il est calculé mais on ne l'utilise pas.

		if (reordered.size() != suppliersListNormalSize) {
			System.err.println(reordered.size() + ", " + suppliersListNormalSize);
			throw new IllegalStateException("Reordered list size is not equal to L.");
		} // TODO on pourrait peut-être supprimer ce test ?

		// Il faut maintenant renouveler partiellement la liste en supprimant
		// les derniers items et en les remplaçant par de nouveaux, tirés au hasard dans
		// la masse.
		suppliers.clear();
		suppliers.addAll(reordered);

		// remove Lowest Ranked Suppliers
		var fromIndex = suppliersListNormalSize - numSuppliersToReject;
		suppliers.subList(fromIndex, suppliersListNormalSize).clear();
		
	}

}
