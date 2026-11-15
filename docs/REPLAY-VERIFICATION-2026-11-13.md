# Replay interruption fix — 2026-11-13

## Verified defect

A rest callback schedules the next move after 250 ms. Previously, stopping and restarting during that pause allowed the old callback to advance the new replay, since it checked only `playing`. A standalone model reproduction returned step 1 before the new playback had received any rest notification. With the fix it remains at step 0.

## Changes

- Each delayed advance belongs to a playback generation; stopping, editing, scrubbing or restarting invalidates earlier work.
- Repeated rest notifications queue only one advance.
- Motion resuming invalidates the old rest delay.
- Stopping when already settled disables continuous rendering. Starting again wakes it.
- Equivalent/partially-invalid text edits also stop replay rather than allowing it to continue behind editing.

## Validation

- `zsh Scripts/test-playback.sh`: 18 checks passed, including an offscreen SCNView sleep/wake check. No app window opened.
- `zsh Scripts/test.sh`: all checks passed, including 854 geometric states and live Windsor forward/reverse settling. Engine files unchanged by this fix.
- A whole-app Swift compile to a temporary executable passed. The ordinary sandbox blocked Apple's SwiftUI compiler macro; the approved unsandboxed compile succeeded.
- `git diff --check`: passed.
- Independent static review found no new guard flaw and identified the related renderer-idle issue, now covered.

No live mouse/keyboard session or packaged-app launch was performed. Installed app and existing `build/KnotStudio.app` were not replaced. Changes are local and uncommitted; no publication or push.

## Continuation

Review the local diff, then rebuild through `Scripts/build.sh` when ready to use it. A future native pass can exercise rapid Space/Space/replay and timeline edits in a visible window. No implementation blocker remains.
