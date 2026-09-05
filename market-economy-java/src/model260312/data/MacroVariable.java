package model260312.data;

public enum MacroVariable {
	
    CONSUMPTION_BUDGET("consumptionBudget"),
    CONSUMPTION_VALUE("consumptionValue"),
    CONSUMPTION_VOLUME("consumptionVolume"),
    PRODUCTION_VALUE("productionValue"),
    PRODUCTION_VOLUME("productionVolume"),
    SECTOR_SIZE("sectorSize"),
    UNSOLD_VOLUME("unsoldVolume"),
    UNSOLD_VOLUME_POSITIF("unsoldVolumePositif"),
    PRODUCT_DESTRUCTION("productDestruction"), 
    PRICE("price"), 
    MAX_PRICE("maxPrice"), 
    MIN_PRICE("minPrice"), 
    SPEED("speed"), 
    LABOR_USED("laborUsed"),
    ;

    private final String csvName;

    MacroVariable(String csvName) {
        this.csvName = csvName;
    }

    public String csvName() {
        return csvName;
    }
    
}
