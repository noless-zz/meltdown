extends XRInterfaceExtension

## An XR interface that reports itself initialized, standing in for the
## headset's OpenXR runtime in the frame_budget runner test (#643). Not a test
## file, so the test runner does not load it.


func _get_name() -> StringName:
	return &"FakeHeadset"


func _is_initialized() -> bool:
	return true
