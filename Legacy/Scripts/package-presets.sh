#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
root="$PWD"
release="KnotStudio-Presets-0.8"
staging="$(mktemp -d /tmp/knotstudio-package.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
package="$staging/$release"
mkdir -p "$package/Source" "$package/Previews" "$package/Evidence" deliverables/premade-0.8
/usr/bin/ditto --norsrc --noextattr -x -k build/KnotStudio.app.zip "$package"
/usr/bin/codesign --verify --strict "$package/KnotStudio.app"
for folder in Sources Scripts Tests Tools docs; do
  /usr/bin/ditto --norsrc --noextattr "$folder" "$package/Source/$folder"
done
cp README.md "$package/README.md"
cp README.md "$package/Source/README.md"
cp docs/PREMADE-0.8-VERIFICATION.md "$package/VERIFICATION.md"
cp deliverables/premade-0.8/*.png "$package/Previews/"
cp artifacts/premade-0.8/final/*.png "$package/Previews/"
mkdir -p "$package/Previews/Initial-0.8"
cp artifacts/premade-0.8/focused-before/*.png "$package/Previews/Initial-0.8/"
cp artifacts/premade-0.8/preset-checks.txt artifacts/premade-0.8/material-audit.txt artifacts/premade-0.8/rendering-checks.txt artifacts/premade-0.8/view-state-checks.txt artifacts/premade-0.8/build.txt artifacts/premade-0.8/source-comparison.txt artifacts/premade-0.8/prior-packages.sha256 "$package/Evidence/"
cp artifacts/checks.txt "$package/Evidence/legacy-checks.txt"
python3 - "$package" <<'PY'
from pathlib import Path
import hashlib,sys,shutil
root=Path(sys.argv[1])
readme=root/'README.md'
readme.write_text(readme.read_text().replace('](docs/', '](Source/docs/').replace('`docs/', '`Source/docs/').replace('## Build and verify', '## Build and verify\n\nRun the following from the packaged `Source` directory (`cd Source`).'))
for p in root.rglob('__pycache__'):shutil.rmtree(p)
for p in root.rglob('.DS_Store'):p.unlink()
files=sorted(p for p in root.rglob('*') if p.is_file())
assert not any('photo-references' in str(p) for p in files)
(root/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in files))
PY
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$package" "deliverables/premade-0.8/$release.zip"
/usr/bin/unzip -t "deliverables/premade-0.8/$release.zip" > artifacts/premade-0.8/archive-test.txt
/usr/bin/ditto --norsrc --noextattr -x -k "deliverables/premade-0.8/$release.zip" "$staging/verify"
/usr/bin/codesign --verify --strict "$staging/verify/$release/KnotStudio.app"
(cd "$staging/verify/$release" && /usr/bin/shasum -a 256 -c SHA256SUMS.txt) > artifacts/premade-0.8/package-hashes.txt
print "Verified deliverables/premade-0.8/$release.zip"
