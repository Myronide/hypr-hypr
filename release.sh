#!/usr/bin/env bash
# Neue Version vorbereiten: Nummer in VERSION erhöhen, Eintrag im CHANGELOG.md, Commit + Tag. Gepusht wird NICHT automatisch.
#   ./release.sh patch "Kurzbeschreibung"    1.0.0 -> 1.0.1   (Fehlerbehebungen)
#   ./release.sh minor "Kurzbeschreibung"    1.0.0 -> 1.1.0   (neue Funktionen)
#   ./release.sh major "Kurzbeschreibung"    1.0.0 -> 2.0.0   (große Umbauten)
# Danach: git push --follow-tags   – die Shells der anderen melden dann das Update.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
kind="${1:-}"; msg="${2:-}"
[[ "$kind" =~ ^(patch|minor|major)$ ]] && [ -n "$msg" ] || { sed -n '2,6p' "$0" | sed 's/^# \?//'; exit 2; }
cur="$(tr -d '[:space:]' < VERSION)"; IFS=. read -r ma mi pa <<< "$cur"
case "$kind" in major) ma=$((ma+1)); mi=0; pa=0;; minor) mi=$((mi+1)); pa=0;; patch) pa=$((pa+1));; esac
new="$ma.$mi.$pa"
echo "$new" > VERSION
# Eintrag direkt unter der Einleitung einfügen (vor dem ersten "## ")
python3 -I - "$new" "$msg" <<'PY'
import sys
new, msg = sys.argv[1:3]
t = open("CHANGELOG.md", encoding="utf-8").read()
i = t.index("\n## ")
open("CHANGELOG.md", "w", encoding="utf-8").write(t[:i] + "\n## %s\n- %s\n" % (new, msg) + t[i:])
PY
git add VERSION CHANGELOG.md
git commit -qm "Version $new: $msg"
git tag -a "v$new" -m "Version $new: $msg"
echo "Version $cur -> $new  (Commit + Tag v$new)"
echo "Zum Veröffentlichen:  git push --follow-tags"
