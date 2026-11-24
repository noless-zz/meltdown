extends RefCounted

## The `fire_debris_look` acceptance check (#1331, GFX-2, GFX-4, GFX-6): at the
## end of a step whose replay set the mine burning, the meltdown fire in the
## main scene burns with particle flames and embers, landed rock and slabs wear
## the surfaces from the shipped effects look, and the debris adds no light.
## It reads the view only; the step's hash checks hold the simulation to its
## pinned values, so the new look cannot have changed it (ARC-1, ARC-2).

const CHECK: String = "fire_debris_look"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var wiring: MeltdownWiring = runner.main.get("meltdown") if runner.main != null else null
	if wiring == null or wiring.debris_view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no meltdown debris"]
	return judge_view(wiring.debris_view, measurements)


## [result, message] for `view`, adding the counts it found to `measurements`.
static func judge_view(view: DebrisView, measurements: Dictionary) -> Array:
	var look: Dictionary = view.effects().look()
	for section: String in DebrisEffectsLook.RANGES:
		if not look.has(section):
			return [AcceptanceReport.RESULT_FAIL, "the debris is drawn without its \"%s\" look" % section]
	var burning: int = 0
	var flaming: int = 0
	var landed: int = 0
	for index: int in view.entry_count():
		var state: DebrisView.EntryState = view.entry_state(index)
		if view.entry_is_fire(index) and state == DebrisView.EntryState.BURNING:
			burning += 1
			var flames: GPUParticles3D = DebrisEffects.flames_of(view.entry(index))
			var embers: GPUParticles3D = DebrisEffects.embers_of(view.entry(index))
			if flames != null and flames.emitting and embers != null and embers.emitting:
				flaming += 1
		elif state == DebrisView.EntryState.SOLID:
			landed += 1
	var lights: int = view.find_children("*", "Light3D", true, false).size()
	measurements["debris_fires_burning"] = burning
	measurements["debris_fires_with_particles"] = flaming
	measurements["debris_landed"] = landed
	measurements["debris_dust_puffs"] = view.effects().landings
	measurements["debris_lights"] = lights
	if burning == 0:
		return [AcceptanceReport.RESULT_FAIL, "no fire burns at the end of the step"]
	if flaming != burning:
		return [AcceptanceReport.RESULT_FAIL, "%d of %d burning fires have no particle flames" % [burning - flaming, burning]]
	var walls: Dictionary = LevelLook.load_or_fallback()
	var rock: StandardMaterial3D = view.material_for(DebrisView.EntryState.SOLID)
	if absf(rock.roughness - float(walls["roughness"])) > 1e-4:
		return [AcceptanceReport.RESULT_FAIL, "the rock is not the walls' rock (roughness %.2f)" % rock.roughness]
	var theme: Dictionary = LevelWallMaterial.load_theme()
	var slab: StandardMaterial3D = view.slab_material_for(DebrisView.EntryState.SOLID)
	if absf(slab.metallic - float(theme["metallic"])) > 1e-4:
		return [AcceptanceReport.RESULT_FAIL, "the slabs are not the walls' metal (metallic %.2f)" % slab.metallic]
	if lights != 0:
		return [AcceptanceReport.RESULT_FAIL, "the debris adds %d lights (GFX-4)" % lights]
	return [AcceptanceReport.RESULT_PASS, "%d fires burning with particles, %d landed, %d dust puffs, no added light" \
		% [burning, landed, view.effects().landings]]
