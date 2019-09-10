# Properties under /consumables/fuel/tank[n]:
# + level-gal_us    - Current fuel load.  Can be set by user code.
# + level-lbs       - OUTPUT ONLY property, do not try to set
# + selected        - boolean indicating tank selection.
# + density-ppg     - Fuel density, in lbs/gallon.
# + capacity-gal_us - Tank capacity
#
# Properties under /engines/engine[n]:
# + fuel-consumed-lbs - Output from the FDM, zeroed by this script
# + out-of-fuel       - boolean, set by this code.


var UPDATE_PERIOD = 0.3;


var update = func {
	if (fuel_freeze) {
		return;
	}

	var consumed_fuel = 0;
	foreach (var e; engines) {
		var fuel = e.getNode("fuel-consumed-lbs");
		consumed_fuel += fuel.getValue();
		fuel.setDoubleValue(0);
	}

	if (!consumed_fuel) {
		return;
	}

	var selected_tanks = [];
	foreach (var t; tanks) {
		var cap = t.getNode("capacity-gal_us").getValue();
		if (cap > 0.01 and t.getNode("selected").getBoolValue()) {
			append(selected_tanks, t);
		}
	}

# Subtract fuel from tanks, set auxilliary properties.  Set out-of-fuel
# when any one tank is dry.
	var out_of_fuel = 0;
	if (size(selected_tanks) == 0) {
		out_of_fuel = 1;
	} else {
		var fuel_per_tank = consumed_fuel / size(selected_tanks);
		foreach (var t; selected_tanks) {
			var ppg = t.getNode("density-ppg").getValue();
			var lbs = t.getNode("level-gal_us").getValue() * ppg;
			lbs = lbs - fuel_per_tank;
			if (lbs < 0) {
				lbs = 0;
# Kill the engines if we're told to, otherwise simply
# deselect the tank.
				if (t.getNode("kill-when-empty", 1).getBoolValue()) {
					out_of_fuel = 1;
				} else {
					t.getNode("selected").setBoolValue(0);
				}
			}
			var gals = lbs / ppg;
			t.getNode("level-gal_us").setDoubleValue(gals);
			t.getNode("level-lbs").setDoubleValue(lbs);
		}
	}

# Total fuel properties
	var lbs = 0;
	var gals = 0;
	var cap = 0;

	foreach (var t; tanks) {
#		var level = t.getNode("level-gal_us").getValue();
#		var density = t.getNode("density-ppg").getValue();
#		t.getNode("level-lbs").setDoubleValue(level * density);
#		print ("level " , level, " density " , density, " lbs ", level * density);
		lbs += t.getNode("level-lbs").getValue();
		gals += t.getNode("level-gal_us").getValue();
		cap += t.getNode("capacity-gal_us").getValue();
	}

	total_lbs.setDoubleValue(lbs);
	total_gals.setDoubleValue(gals);
	total_norm.setDoubleValue(gals / cap);

	foreach (var e; engines) {
		e.getNode("out-of-fuel").setBoolValue(out_of_fuel);
	}
}


var loop = func {
	update();
	settimer(loop, UPDATE_PERIOD);
}


var init_double_prop = func(node, prop, val) {
	if (node.getNode(prop) != nil) {
		val = num(node.getNode(prop).getValue());
	}
	node.getNode(prop, 1).setDoubleValue(val);
}



var tanks = [];
var engines = [];
var fuel_freeze = nil;
var total_gals = nil;
var total_lbs = nil;
var total_norm = nil;


var L = setlistener("/sim/signals/fdm-initialized", func {
	removelistener(L);

	setlistener("/sim/freeze/fuel", func(n) { fuel_freeze = n.getBoolValue() }, 1);

	total_gals = props.globals.getNode("/consumables/fuel/total-fuel-gals", 1);
	total_lbs = props.globals.getNode("/consumables/fuel/total-fuel-lbs", 1);
	total_norm = props.globals.getNode("/consumables/fuel/total-fuel-norm", 1);

	engines = props.globals.getNode("engines", 1).getChildren("engine");
	foreach (var e; engines) {
		e.getNode("fuel-consumed-lbs", 1).setDoubleValue(0);
		e.getNode("out-of-fuel", 1).setBoolValue(0);
	}

	foreach (var t; props.globals.getNode("/consumables/fuel", 1).getChildren("tank")) {
		if (!size(t.getChildren())) {
			continue;           # skip native_fdm.cxx generated zombie tanks
		}
		append(tanks, t);
		init_double_prop(t, "level-gal_us", 0.0);
		init_double_prop(t, "level-lbs", 0.0);
		init_double_prop(t, "capacity-gal_us", 0.01); # not zero (div/zero issue)
			init_double_prop(t, "density-ppg", 6.0);      # gasoline

			if (t.getNode("selected") == nil) {
				t.getNode("selected", 1).setBoolValue(1);
			}
	}

	loop();
});


