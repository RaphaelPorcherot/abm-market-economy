package model260312.models;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import model260312.agents.Agent;
import model260312.data.MacroKey;
import model260312.parameters.Parameters;

public abstract class Model {

	final protected int nSector;

	final protected Map<MacroKey, Float> data = new HashMap<>();

	public Model(Parameters params) {
		this.nSector = params.nSector();
	}

	public abstract void run(List<Agent> population);

	final public Map<MacroKey, Float> getData() {
		return data;
	}
	
	protected Boolean respectsRicardo(Agent A, Agent B) {
		var ApI = A.productionIndex();
		var BpI = B.productionIndex();
		
		if (ApI ==  BpI) {
			return null;
		}
		
		var rA = A.productivity(ApI)/A.productivity(BpI);
		var rB = B.productivity(ApI)/B.productivity(BpI);
		
		return rA>=rB;
	}


}
