package model260312.agents;

import java.util.List;
import java.util.Random;

public interface World {

	Random random();

	Agent pickRandomAgent();

	List<Agent> pickRandomAgents(int k);

	int getNumberOfAgents();

}
