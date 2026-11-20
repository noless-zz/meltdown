class_name FakeJavaActivity
extends RefCounted

## Stands in for the Android activity in the `AndroidInstaller` tests (#719):
## answers the package name and the install permission, and remembers the last
## call so `FakeAndroidInstaller` can say whether that call threw.

var package: String = "io.example.meltdown"
var allowed: bool = true
var last_call: String = ""


func getPackageName() -> String:
	last_call = "getPackageName"
	return package


func getPackageManager() -> Object:
	last_call = "getPackageManager"
	return self


func canRequestPackageInstalls() -> bool:
	last_call = "canRequestPackageInstalls"
	return allowed
