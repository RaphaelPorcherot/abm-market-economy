package model260312.data;

import java.util.HashMap;
import java.util.Map;

public class MacroData {

	// === Données macro ===
	private final float[] consumptionBudget;
	private final float[] consumptionValue;
	private final float[] consumptionVolume;
	private final float[] laborUsed;
	private final float[] productionValue;
	private final float[] productionVolume;
	private final float[] sectorSize;
	private final float[] unsoldVolume;
	private final float[] unsoldVolumePositif;
	private final float[] productDestruction;
	private final float[] price;
	private final float[] maxPrice;
	private final float[] minPrice;
	private final float[] speed;

	private final int nSector;
	private final int t;

	// === Construction ===
	public MacroData(int nSector, int period) {
		this.t = period;
		this.nSector = nSector;

		consumptionBudget = new float[nSector];
		consumptionValue = new float[nSector];
		consumptionVolume = new float[nSector];
		laborUsed = new float[nSector];
		productionValue = new float[nSector];
		productionVolume = new float[nSector];
		sectorSize = new float[nSector];
		unsoldVolume = new float[nSector];
		unsoldVolumePositif = new float[nSector];
		productDestruction = new float[nSector];
		price = new float[nSector];
		maxPrice = new float[nSector];
		minPrice = new float[nSector];
		speed = new float[nSector];

		// initialisation à NaN
		initNaN(consumptionBudget);
		initNaN(consumptionValue);
		initNaN(consumptionVolume);
		initNaN(laborUsed);
		initNaN(productionValue);
		initNaN(productionVolume);
		initNaN(sectorSize);
		initNaN(unsoldVolume);
		initNaN(unsoldVolumePositif);
		initNaN(productDestruction);
		initNaN(price);
		initNaN(minPrice);
		initNaN(maxPrice);
		initNaN(speed);
	}

	// === Accumulation sécurisée ===
	private float add(float base, float valeur) {
		return Float.isNaN(base) ? valeur : base + valeur;
	}

	public void addValue(MacroVariable var, int sector, float valeur) {
		switch (var) {
		case CONSUMPTION_BUDGET -> consumptionBudget[sector] = add(consumptionBudget[sector], valeur);
		case CONSUMPTION_VALUE -> consumptionValue[sector] = add(consumptionValue[sector], valeur);
		case CONSUMPTION_VOLUME -> consumptionVolume[sector] = add(consumptionVolume[sector], valeur);
		case LABOR_USED -> laborUsed[sector] = add(laborUsed[sector], valeur);
		case PRODUCTION_VALUE -> productionValue[sector] = add(productionValue[sector], valeur);
		case PRODUCTION_VOLUME -> productionVolume[sector] = add(productionVolume[sector], valeur);
		case SECTOR_SIZE -> sectorSize[sector] = add(sectorSize[sector], valeur);
		case UNSOLD_VOLUME -> unsoldVolume[sector] = add(unsoldVolume[sector], valeur);
		case UNSOLD_VOLUME_POSITIF -> unsoldVolumePositif[sector] = add(unsoldVolumePositif[sector], valeur);
		case PRODUCT_DESTRUCTION -> productDestruction[sector] = add(productDestruction[sector], valeur);
		case PRICE -> price[sector] = add(price[sector], valeur);
		case MAX_PRICE -> {
			if (Float.isNaN(maxPrice[sector]) || valeur > maxPrice[sector]) {
				maxPrice[sector] = valeur;
			}
		}
		case MIN_PRICE -> {
			if (Float.isNaN(minPrice[sector]) || valeur < minPrice[sector]) {
				minPrice[sector] = valeur;
			}
		}
		case SPEED -> speed[sector] = add(speed[sector], valeur);
		}
	}

	// === Export pour CSV / R ===
	public Map<MacroKey, Float> getData() {
		Map<MacroKey, Float> data = new HashMap<>();

		for (int sector = 0; sector < nSector; sector++) {
			for (MacroVariable var : MacroVariable.values()) {
				float val = getValue(var, sector);
				data.put(new MacroKey(t, var, sector), Float.isNaN(val) ? null : val);
			}
		}
		return data;
	}

	// === Accès aux valeurs ===
	private float getValue(MacroVariable var, int sector) {
		return switch (var) {
		case CONSUMPTION_BUDGET -> consumptionBudget[sector];
		case CONSUMPTION_VALUE -> consumptionValue[sector];
		case CONSUMPTION_VOLUME -> consumptionVolume[sector];
		case LABOR_USED -> laborUsed[sector];
		case PRODUCTION_VALUE -> productionValue[sector];
		case PRODUCTION_VOLUME -> productionVolume[sector];
		case SECTOR_SIZE -> sectorSize[sector];
		case UNSOLD_VOLUME -> unsoldVolume[sector];
		case UNSOLD_VOLUME_POSITIF -> unsoldVolumePositif[sector];
		case PRODUCT_DESTRUCTION -> productDestruction[sector];
		case PRICE -> price[sector];
		case MAX_PRICE -> maxPrice[sector];
		case MIN_PRICE -> minPrice[sector];
		case SPEED -> speed[sector];
		};
	}

	private void initNaN(float[] array) {
		for (int i = 0; i < array.length; i++)
			array[i] = Float.NaN;
	}

	public void setValue(MacroVariable var, int sector, float valeur) {
		switch (var) {
		case CONSUMPTION_BUDGET -> consumptionBudget[sector] = valeur;
		case CONSUMPTION_VALUE -> consumptionValue[sector] = valeur;
		case CONSUMPTION_VOLUME -> consumptionVolume[sector] = valeur;
		case PRODUCTION_VALUE -> productionValue[sector] = valeur;
		case PRODUCTION_VOLUME -> productionVolume[sector] = valeur;
		case SECTOR_SIZE -> sectorSize[sector] = valeur;
		case UNSOLD_VOLUME -> unsoldVolume[sector] = valeur;
		case UNSOLD_VOLUME_POSITIF -> unsoldVolumePositif[sector] = valeur;
		case PRODUCT_DESTRUCTION -> productDestruction[sector] = valeur;
		case PRICE -> price[sector] = valeur;
		case SPEED -> speed[sector] = valeur;
		default -> throw new IllegalArgumentException("Unexpected value: " + var);
		}
	}

}
