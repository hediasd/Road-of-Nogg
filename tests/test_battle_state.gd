extends GutTest

func test_serialization():
	var sim = BattleSimulator.new()
	sim.state.setup_board(Vector2i(4, 4))
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	
	var state_dict = sim.state.serialize_state()
	
	assert_true(state_dict.has("monsters"), "State should contain 'monsters' key")
	assert_eq(state_dict["monsters"].size(), 1, "There should be exactly 1 monster serialized")
