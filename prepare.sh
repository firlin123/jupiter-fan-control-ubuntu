#!/bin/bash

PKGBASE="jupiter-fan-control"
PKGVER="20260422.2"
PKGREL="2"

TAG="matts/7.2-fix"
SRCNAME="jupiter-fan-control"

pkg_name="$PKGBASE-$PKGVER"
pkg_full="$pkg_name-$PKGREL"
script=$(realpath "$0")

# Generate debian changelog from git log
function generate_changelog {
    seen_hashes=()
    out=""

    all_tags=$(git tag --list)

    if ! grep -qxF "$TAG" <<< "$all_tags"; then
        if [[ -z "$all_tags" ]]; then
            all_tags="$TAG"
        else
            all_tags="$all_tags"$'\n'"$TAG"
        fi
    fi

    sorted_tags=$(
        echo "$all_tags" | while read -r t; do
            if [[ -z "$t" ]]; then continue; fi
            v="${t#fancontrol-}"
            v="${v#fan-control-}"
            echo "$v $t"
        done | sort -V | awk '{print $2}'
    )

    while read -r tag; do
        if [[ -z "$tag" ]]; then
            continue
        fi

        if ! [[ "$tag" =~ ^(fan-?control-)?[0-9]{8}(\.[0-9]+)?$ ]] && [[ "$tag" != "$TAG" ]]; then
            continue
        fi

        changelog_ver="${tag#fancontrol-}"
        changelog_ver="${changelog_ver#fan-control-}"

        if ! [[ "$tag" =~ ^(fan-?control-)?[0-9]{8}(\.[0-9]+)?$ ]]; then
            changelog_ver="${PKGVER}-${PKGREL}"
        fi

        change=""

        tag_date=$(git log -1 --format=%ad --date=rfc "$tag")

        change+="${PKGBASE} (${changelog_ver}) unstable; urgency=medium"
        change+=$'\n\n'

        has_commits=false
        while read -r commit; do
            hash=$(echo "$commit" | cut -d' ' -f1)
            if [[ " ${seen_hashes[*]} " == *" $hash "* ]]; then
                continue
            fi
            change+="  * $commit"
            change+=$'\n'
            seen_hashes+=("$hash")
            has_commits=true
        done < <(git log "$tag" --pretty=format:"%h - %s (%an <%ae>)" --no-merges)

        if ! $has_commits; then
            continue
        fi

        change+=$'\n'
        change+=" -- $(git log -1 --format='%an <%ae>' "$tag")  $tag_date"
        change+=$'\n\n'

        out="$change$out"
    done <<< "$sorted_tags"
    echo "$out"
}

# Check dependencies
missing=()
if ! command -v wget &> /dev/null; then
    missing+=("wget")
fi
if ! command -v git &> /dev/null; then
    missing+=("git")
fi
if ! command -v dpkg-buildpackage &> /dev/null; then
    missing+=("dpkg-dev")
fi
if ! command -v dh &> /dev/null; then
    missing+=("debhelper")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "Install them with 'sudo apt install ${missing[*]}'"
    exit 1
fi

echo "Downloading source package..."
wget "https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-main/$pkg_full.src.tar.gz"
tar -xvf "$pkg_full.src.tar.gz"
cd "$PKGBASE"

# Convert PKGBUILD maintainer list to debian format
maintainer=""
uploaders=""
while IFS= read -r line; do
    if [[ $line =~ ^#\ Maintainer:[[:space:]]*(.*) ]]; then
        clean_name="${BASH_REMATCH[1]}"

        if [[ -z $maintainer ]]; then
            maintainer="$clean_name"
        else
            if [[ -n $uploaders ]]; then
                uploaders+=$',\n '
            fi
            uploaders+="$clean_name"
        fi
    fi
done < PKGBUILD

echo "Preparing source..."
mv "$SRCNAME" "$SRCNAME.orig"
mkdir "$pkg_name"
mv "$SRCNAME.orig" "$pkg_name/.git"
cd "$pkg_name"
git config --unset core.bare
git checkout "$TAG"
find . -name "*.py" -exec sed -i 's|#!/usr/bin/python|#!/usr/bin/python3|' {} \;
cp "$script" prepare.sh
cat > README.md <<'EOF'
# Steam Deck fan control for debian-based distributions

`jupiter-fan-control` package from SteamOS, repackaged for Ubuntu (and possibly other Debian-based distributions, but haven't tested it on anything else). Controls the fan speed more intelligently than the default BIOS fan curve, based on the temperature of various components, and the current power state of the system. Relies on steamdeck hwmon. Please install the [DKMS module](https://github.com/firlin123/steamdeck-dkms) to get the necessary hwmon support (or use SteamOS kernel, which has it built-in). Works only on Steam Deck, and won't do anything on other hardware.

## Installation
Download the latest .deb file from releases page and install it.

## Building from source
```bash
sudo apt update
sudo apt install -y dpkg-dev debhelper git
git clone https://github.com/firlin123/jupiter-fan-control-deb.git
cd jupiter-fan-control-deb
dpkg-buildpackage -us -uc
```

## Pulling updates from upstream
```bash
sudo apt update
sudo apt install -y dpkg-dev debhelper git wget
git clone https://github.com/firlin123/jupiter-fan-control-deb.git
cp jupiter-fan-control-deb/prepare.sh ./
# Edit the prepare.sh file to set the version variables to the desired version, then run it.
./prepare.sh
cd jupiter-fan-control-deb
rm -r *
mv ../jupiter-fan-control/*/* ./
git add .
# Choose a desired commit message, usually - the version number.
git commit -m "<package version>"
git push
```
EOF

echo "Generating debian files..."
mkdir -p debian
mkdir -p debian/source
echo '1.0' > debian/source/format
echo '10' > debian/compat
cat > debian/control <<EOF
Source: $PKGBASE
Section: utils
Priority: optional
Maintainer: $maintainer
Uploaders: $uploaders
Standards-Version: 4.7.0

Package: $PKGBASE
Architecture: all
Depends: python3-yaml, python3 (>= 3.11)
Description: Steam Deck fan control for debian-based distributions
 Controls the fan speed more intelligently than the default BIOS fan curve, based on the temperature of various components, and the current power state of the system. Relies on steamdeck hwmon. Please install the DKMS module to get the necessary hwmon support (or use SteamOS kernel, which has it built-in). Works only on Steam Deck, and won't do anything on other hardware.
EOF
cat > debian/rules <<EOF
#!/usr/bin/make -f

%:
	dh \$@

override_dh_install:
	mkdir -p \$(CURDIR)/debian/$PKGBASE
	cp -r \$(CURDIR)/usr \$(CURDIR)/debian/$PKGBASE/
EOF
chmod +x debian/rules
generate_changelog > debian/changelog

echo "Done. You can now build the package with 'cd $pkg_name && dpkg-buildpackage -us -uc'"
cd ../..
