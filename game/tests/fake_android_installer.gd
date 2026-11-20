class_name FakeAndroidInstaller
extends AndroidInstaller

## The real `AndroidInstaller` with a fake activity and a fake exception in
## place of Java, so its own checks run off Android (#719). The call named in
## `throw_on` throws `exception_text` once.

var throw_on: String = ""
var exception_text: String = "java.lang.SecurityException: package hidden"


func _init(fake: FakeJavaActivity) -> void:
	super(null)
	activity = fake


func pending_exception() -> Object:
	var fake: FakeJavaActivity = activity as FakeJavaActivity
	if throw_on == "" or fake.last_call != throw_on:
		return null
	fake.last_call = ""
	return FakeJavaException.new(exception_text)
