class_name InstallerProbeBridge
extends RefCounted

## The Android calls the installer probe (#130, #595) makes, one method per
## step, so the step order and the log lines can be tested off Android with a
## fake. `InstallerProbeJava` is the real one; this base fails every step, which
## keeps a half-written fake from looking like a success.

## Why the last step failed: the exact Java exception when one was thrown,
## otherwise a short reason. Read only after a step reported failure.
var failure: String = ""


## The path of the running app's own APK, or "" on failure.
func source_path() -> String:
	failure = "not implemented"
	return ""


## The size in bytes of the file at `path` as Java sees it, or -1 when it is
## missing, unreadable or the call failed.
func source_size(_path: String) -> int:
	failure = "not implemented"
	return -1


## The app's files directory (what the FileProvider serves), or "" on failure.
func files_dir() -> String:
	failure = "not implemented"
	return ""


## Copies `source` to `target` and returns the bytes written, or -1 on failure.
func copy(_source: String, _target: String) -> int:
	failure = "not implemented"
	return -1


## Builds the content URI for `target` and keeps it for `start_installer()`.
## Returns the URI as text, or "" on failure.
func content_uri(_target: String) -> String:
	failure = "not implemented"
	return ""


## Starts the package installer on the URI from `content_uri()`.
func start_installer() -> bool:
	failure = "not implemented"
	return false
