extends RefCounted

## The `hub_sounds` check (#1401, AUD-1, CRW-2, CRF-3, CRF-4, DEV-6, decision
## record 0005), lane-c's file under `acceptance/checks/`. In
## `suites/m6/base.json` it follows `hub_stations` on that step:
##
##     {"id": "hub_stations", ..., "checks": ["no_script_errors", "hub_stations", "hub_sounds"]}
##
## `hub_stations` builds a weapon at the craft station, mounts it at the fit
## station and launches, all through the scene's own controls. This check then
## reads what the stations' sounds (`HubWiring.sounds`) requested on the way:
## taking a station into use must have requested `select`, the build `crafted`
## at the craft station, the mount `mounted` at the fit station and the launch
## row `launch`, in that order. Whether they sound soft and physical stays a
## headset check.

const CHECK: String = "hub_sounds"
## Each expected sound and the station it must come from ("" for any).
const EXPECTED: Array[Array] = [["select", ""], ["crafted", "craft"], ["mounted", "fit"], ["launch", "launch"]]


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var hub: HubWiring = runner.main.get("hub") as HubWiring if runner.main != null else null
	if hub == null or hub.sounds == null:
		return [AcceptanceReport.RESULT_FAIL, "the hub has no station sounds"]
	var heard: Array[String] = hub.sounds.requested
	var at: Array[String] = hub.sounds.requested_at
	measurements["hub_sounds"] = ",".join(heard)
	var from: int = 0
	for want: Array in EXPECTED:
		var found: int = -1
		for i: int in range(from, heard.size()):
			if heard[i] == want[0] and (want[1] == "" or at[i] == want[1]):
				found = i
				break
		if found < 0:
			var where: String = " at the %s station" % want[1] if want[1] != "" else ""
			return [AcceptanceReport.RESULT_FAIL, "no %s sound%s was requested after the earlier ones: %s" % [
				want[0], where, heard]]
		from = found + 1
	return [AcceptanceReport.RESULT_PASS, "requested select, crafted, mounted and launch at their stations (%d sounds)" %
		heard.size()]
