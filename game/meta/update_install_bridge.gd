class_name UpdateInstallBridge
extends RefCounted

## The Android calls that hand an APK to the package installer (#648, DEV-8,
## PLT-1), one method per step, so `UpdateInstall` can be tested off Android
## with a fake. `AndroidInstaller` is the real one; this base fails every step,
## which keeps a half-written fake from looking like a success.

const ALLOWED: int = 1
const NOT_ALLOWED: int = 0
const UNKNOWN: int = -1

## Why the last step failed: the exact Java exception when one was thrown,
## otherwise a short reason. Read only after a step reported failure.
var failure: String = ""


## Whether this app may ask to install packages: `ALLOWED`, `NOT_ALLOWED`, or
## `UNKNOWN` when the call failed.
func may_install() -> int:
	failure = "not implemented"
	return UNKNOWN


## Opens the system screen where the pilot allows installs from this app.
func ask_install_permission() -> bool:
	failure = "not implemented"
	return false


## Builds the content URI for `target` and keeps it for `start_installer()`.
## Returns the URI as text, or "" on failure.
func content_uri(_target: String) -> String:
	failure = "not implemented"
	return ""


## Starts the package installer on the URI from `content_uri()`.
func start_installer() -> bool:
	failure = "not implemented"
	return false
