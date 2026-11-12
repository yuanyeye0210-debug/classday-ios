#!/usr/bin/env bash
# Publish the unsigned IPA to classday-releases and prune GitHub Releases.
# Runs from GitHub Actions after the IPA exists in dist/.
# A push that is not a version bump on main or a v* tag does nothing.
# If RELEASES_TOKEN is unset, publishing is skipped and the build still succeeds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
cd "$REPO"

CURRENT="$(tr -d '[:space:]' < Classday/VERSION)"
PARENT=""
if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  PARENT="$(git show HEAD^:Classday/VERSION 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -z "$PARENT" ]]; then
    PARENT="$(git show HEAD^:Classday/Classday.xcodeproj/project.pbxproj 2>/dev/null \
      | sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
      | head -n 1 \
      | tr -d '[:space:]"' || true)"
  fi
fi

DECISION="$(python3 "$ROOT/Tools/publish_release.py" should-publish \
  --ref "${GITHUB_REF:-}" \
  --current "$CURRENT" \
  --parent "$PARENT")"
if [[ "$DECISION" != "publish" ]]; then
  echo "Not a release ($DECISION)."
  echo "Current version is ${CURRENT}, parent is ${PARENT:-<none>}, ref is ${GITHUB_REF:-<unset>}."
  echo "Skipping classday-releases publish and GitHub Release prune."
  exit 0
fi

echo "Release ${CURRENT} (parent ${PARENT:-<none>}, ref ${GITHUB_REF:-<unset>})."

if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "Not running inside GitHub Actions. Refusing to prune releases or push to classday-releases."
  exit 0
fi

# Same-repo release prune uses the Actions token. It does not need RELEASES_TOKEN.
if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  tags_file="$(mktemp)"
  gh release list --limit 200 --json tagName --jq '.[].tagName' > "$tags_file"
  deletes_file="$(mktemp)"
  python3 "$ROOT/Tools/publish_release.py" plan-deletes --current "$CURRENT" --tags-file "$tags_file" > "$deletes_file"
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    echo "Deleting GitHub Release ${tag} (keeping current and previous only)."
    gh release delete "$tag" --yes --repo "${GITHUB_REPOSITORY:?}" || exit 1
  done < "$deletes_file"
  rm -f "$tags_file" "$deletes_file"
else
  echo "gh or GITHUB_TOKEN is unavailable, so GitHub Release prune was skipped."
fi

if [[ -z "${RELEASES_TOKEN:-}" ]]; then
  echo "::notice title=SideStore publish skipped::RELEASES_TOKEN is not set. The unsigned IPA is still uploaded as a workflow artifact. To publish Classday-v${CURRENT}.ipa and apps.json to yuanyeye0210-debug/classday-releases, add a repository Actions secret named RELEASES_TOKEN with Contents read and write on that repository. The build is not failing because the secret is missing."
  exit 0
fi

IPAS=()
while IFS= read -r ipa; do
  [[ -z "$ipa" ]] && continue
  IPAS+=("$ipa")
done < <(find "$REPO/dist" -maxdepth 1 -type f -name 'Classday-v*.ipa' | sort)
if [[ ${#IPAS[@]} -ne 1 ]]; then
  echo "Expected exactly one dist/Classday-v*.ipa, found ${#IPAS[@]}." >&2
  exit 1
fi

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
git clone --depth 1 https://github.com/yuanyeye0210-debug/classday-releases.git "$workdir/classday-releases"
DATE="$(git -C "$REPO" show -s --format=%cs HEAD)"
python3 "$ROOT/Tools/publish_release.py" update \
  --releases "$workdir/classday-releases" \
  --ipa "${IPAS[0]}" \
  --changelog "$ROOT/ClassdayCore/Sources/ClassdayCore/ScheduleExtras.swift" \
  --icon "$ROOT/ClassdayApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png" \
  --date "$DATE"

cd "$workdir/classday-releases"
git add -A
if git diff --cached --quiet; then
  echo "classday-releases already has this IPA and apps.json."
  exit 0
fi
git -c user.email="classday-release@users.noreply.github.com" -c user.name="Classday release" \
  commit -m "Publish Classday v${CURRENT}"
auth=(-c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${RELEASES_TOKEN}")
if ! git "${auth[@]}" push origin HEAD:main; then
  git "${auth[@]}" pull --rebase origin main
  git "${auth[@]}" push origin HEAD:main
fi
echo "Published Classday v${CURRENT} to classday-releases."
