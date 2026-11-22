extends RefCounted

## The ship a fully progressed profile starts a run with, for the bot run sweep
## (#1091, CRW-3, CRF-4, CRW-1): read a profile and a fitting from the paths the
## sweep is given and build the tuning exactly as a run level does, through
## `RunShip` and so `RunStartShip.build` (#1057). CRW-3 says progression must
## never trivialise early levels; flying this ship beside the plain one is how
## tuning gets a number for that.
##
## Unlike a run, the sweep refuses anything it would have to leave out: a
## missing or unreadable file, or a fitting `RunStartShip` drops, would measure
## the plain ship under the fitted name.


## {"tuning": ShipTuning, "error": ""} for the ship built from the profile at
## `profile_path`, the fitting at `fitting_path` and the shipped crew roles; on
## a problem, {"tuning": null, "error": <message naming the file>}.
static func fitted(profile_path: String, fitting_path: String,
		roles_path: String = CrewRoles.ROLES_FILE) -> Dictionary:
	if not FileAccess.file_exists(profile_path):
		return _failed("profile %s: not found" % profile_path)
	var profiles: ProfileStore = ProfileStore.new(profile_path)
	var profile: Profile = profiles.load_profile()
	if profiles.message != "":
		return _failed("profile %s: %s" % [profile_path, profiles.message])
	if not FileAccess.file_exists(fitting_path):
		return _failed("fitting %s: not found" % fitting_path)
	var fittings: FittingStore = FittingStore.new(fitting_path)
	fittings.load_fitting()
	if fittings.message != "":
		return _failed("fitting %s: %s" % [fitting_path, fittings.message])
	var roles: CrewRoles = CrewRoles.parse_json(FileAccess.get_file_as_string(roles_path))
	if roles.error != "":
		return _failed("crew roles %s: %s" % [roles_path, roles.error])
	var ship: RunShip = RunShip.new()
	ship.fittings = fittings
	var tuning: ShipTuning = ship.tuning_for(profile, roles)
	if not ship.notes.is_empty():
		return _failed("fitted ship from %s and %s: %s" % [profile_path, fitting_path,
				"; ".join(ship.notes)])
	if tuning == null or tuning.error != "":
		return _failed("fitted ship from %s and %s: the ship file is rejected" % [
				profile_path, fitting_path])
	return {"tuning": tuning, "error": ""}


static func _failed(message: String) -> Dictionary:
	return {"tuning": null, "error": message}
