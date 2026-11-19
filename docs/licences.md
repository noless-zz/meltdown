# Third-party and generated assets

Every dependency, addon and asset is listed here before it is merged (see `CLAUDE.md`).
Free assets and AI-generated or AI-modified assets only.

| Item | Path | Source | Licence | AI tool, if generated or modified | Added in |
| --- | --- | --- | --- | --- | --- |
| Godot Engine | not vendored | https://godotengine.org | MIT | | setup |
| Monado OpenXR runtime | not vendored; installed by the `xr-smoke` CI job from the Ubuntu archive | https://monado.freedesktop.org | BSL-1.0 | | #26 |
| Mesa lavapipe (`mesa-vulkan-drivers`) | not vendored; installed by the `xr-smoke` CI job | https://mesa3d.org | MIT | | #26 |
| Xvfb | not vendored; installed by the `xr-smoke` CI job | https://www.x.org | MIT (X11) | | #26 |
| Godot OpenXR Vendors plugin 5.2.0-stable (`godotopenxrvendorsaddon.zip`, SHA-256 `2a3958fff0de2dbdc4f1a036b5e4cfcea12ae7e45f8deebf4b45e5e9718c4e35`) | not vendored; `tools/fetch_vendors_plugin.sh` downloads it into the git-ignored `game/addons/godotopenxrvendors/` for the `quest-apk` CI job and local Quest builds | https://github.com/GodotVR/godot_openxr_vendors/releases/tag/5.2.0-stable | MIT | | #10 |
| Meta XR Simulator | not vendored; installed by the owner on his `quest-pc` runner and used by the `simulator` job of `device-acceptance.yml` when it is the active OpenXR runtime | https://developers.meta.com/horizon/documentation/native/xrsim-intro/ | Meta's SDK licence, accepted by the owner at install | | #154 |
