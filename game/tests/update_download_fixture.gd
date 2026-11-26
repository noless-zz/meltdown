extends RefCounted

## What the update download tests share (#647, DEV-8): a fake downloader serving
## an APK and its checksum in place of GitHub, and the checks on what is left on
## disk. Not a test file, so the runner does not load it (split out, #1287).

const DIR: String = "user://test_update_download"
const APK_URL: String = "https://github.com/noless-zz/meltdown/releases/download/main-latest/meltdown-quest-debug.apk"
const SHA_URL: String = APK_URL + ".sha256"
const COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"


static func dir() -> String:
	var path: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func apk_bytes(size: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(size)
	for i: int in size:
		bytes[i] = (i * 31 + 7) % 251
	return bytes


static func sha_line(bytes: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return ("%s  meltdown-quest-debug.apk\n" % context.finish().hex_encode()).to_utf8_buffer()


static func available() -> Dictionary:
	return {
		"status": UpdateCheck.STATUS_UPDATE_AVAILABLE,
		"reason": "",
		"commit": COMMIT,
		"apk_url": APK_URL,
		"sha256_url": SHA_URL,
	}


## A fake serving a matching APK and checksum, and a download using it.
static func setup(apk: PackedByteArray) -> Array:
	var fake: FakeUpdateDownloader = FakeUpdateDownloader.new()
	fake.bodies[APK_URL] = apk
	fake.bodies[SHA_URL] = sha_line(apk)
	var download: UpdateDownload = UpdateDownload.new(fake, dir())
	download.cancel()
	for path: String in [download.apk_path(), download.checksum_path()]:
		DirAccess.remove_absolute(path)
	return [fake, download]


static func run_steps(download: UpdateDownload, limit: int) -> int:
	var steps: int = 0
	while download.is_busy() and steps < limit:
		download.step()
		steps += 1
	return steps


static func no_files(download: UpdateDownload) -> String:
	for path: String in [download.apk_path(), download.checksum_path()]:
		if FileAccess.file_exists(path):
			return "%s was left behind" % path
	return ""
