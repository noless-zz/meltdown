class_name RunBanking
extends RefCounted

## Puts what a run hands over on an escape (`RunState.advance`) into the profile
## (CRF-2, RUN-7, #977). Saving the profile to disk stays with `ProfileStore`.


## Adds `counts` to `profile`'s banked components. Returns "" or the reason it
## refused; on refusal the profile is unchanged, because `Profile.bank` checks
## every entry before it adds any.
static func bank_escape(profile: Profile, counts: Dictionary) -> String:
	if profile == null:
		return "no profile to bank into"
	if not profile.bank(counts):
		return "profile refused the counts %s: ids must be non-empty strings and counts whole numbers of 0 or more" % JSON.stringify(counts, "", true)
	return ""
