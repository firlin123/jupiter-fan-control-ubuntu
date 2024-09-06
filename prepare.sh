#!/bin/bash

PKGBASE="jupiter-fan-control"
PKGVER="20240523.3"
PKGREL="2"

TAG="20240523.3"
SRCNAME="jupiter-fan-control"

# Get full path to this script
SCRIPT=$(realpath $0)

# Generate debian changelog from git log
function generate-changelog {
    SEEN_HASHES=()
    OUT=""
    while read TAG; do
        if ! [[ "$TAG" =~ ^[0-9]{8}(\.[0-9]+)?$ ]]; then
            continue
        fi

        CHANGE=""

        TAG_DATE=$(git log -1 --format=%ad --date=rfc "$TAG")

        COMMITS=$(git log "$TAG" --pretty=format:"%h - %s (%an)" --no-merges)

        CHANGE+="${PKGBASE} (${TAG}) unstable; urgency=medium"
        CHANGE+="\n\n"

        HAS_COMMITS=false
        while read COMMIT; do
            HASH=$(echo "$COMMIT" | cut -d' ' -f1)
            if [[ " ${SEEN_HASHES[*]} " == *" $HASH "* ]]; then
                continue
            fi
            CHANGE+="  * $COMMIT"
            CHANGE+="\n"
            SEEN_HASHES+=("$HASH")
            HAS_COMMITS=true
        done < <(git log "$TAG" --pretty=format:"%h - %s (%an <%ae>)" --no-merges)
        if ! $HAS_COMMITS; then
            continue
        fi

        CHANGE+="\n"
        CHANGE+=" -- $(git log -1 --format='%an <%ae>' "$TAG")  $TAG_DATE"
        CHANGE+="\n\n"

        OUT="$CHANGE$OUT"
    done < <(git tag --list --sort=v:refname)
    echo -e "$OUT"
}

# Check dependencies
MISSING=()
if ! command -v wget &> /dev/null; then
    MISSING+=("wget")
fi
if ! command -v git &> /dev/null; then
    MISSING+=("git")
fi
if ! command -v dpkg-buildpackage &> /dev/null; then
    MISSING+=("dpkg-dev")
fi
if ! command -v dh &> /dev/null; then
    MISSING+=("debhelper")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Missing dependencies: ${MISSING[@]}"
    echo "Install them with 'sudo apt install ${MISSING[@]}'"
    exit 1
fi

echo "Downloading source package..."
wget "https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-main/$PKGBASE-$PKGVER-$PKGREL.src.tar.gz"
tar -xvf "$PKGBASE-$PKGVER-$PKGREL.src.tar.gz"
cd "$PKGBASE"

# Convert PKGBUILD maintainer list to debian format
MAINTAINERS=""
while IFS= read -r line; do
    if [[ $line == \#\ Maintainer:* ]]; then
        if [[ ! -z $MAINTAINERS ]]; then
            MAINTAINERS+=", "
        fi
        MAINTAINERS+="$(echo $line | cut -d' ' -f3-)"
    fi
done < PKGBUILD

echo "Preparing source..."
mv "$SRCNAME" "$SRCNAME.orig"
mkdir "$PKGBASE-$PKGVER"
mv "$SRCNAME.orig" "$PKGBASE-$PKGVER/.git"
cd "$PKGBASE-$PKGVER"
git config --unset core.bare
git checkout "$TAG"
find . -name "*.py" -exec sed -i 's|#!/usr/bin/python|#!/usr/bin/python3|' {} \;
cp "$SCRIPT" prepare.sh
echo "# $PKGBASE-ubuntu" > README.md
sed -i 's/"""Calculates PID value for given reference feedback/r"""Calculates PID value for given reference feedback/' usr/share/jupiter-fan-control/PID.py

echo "Generating debian files..."
mkdir -p debian
mkdir -p debian/source
echo -e '1.0' > debian/source/format
echo -e '10' > debian/compat
echo 'Source: '"$PKGBASE"'
Section: utils
Priority: optional
Maintainer: '"$MAINTAINERS"'
Standards-Version: 4.7.0

Package: '"$PKGBASE"'
Architecture: all
Depends: python3-yaml, python3 (>= 3.11)
Description: Jupiter fan controller
' > debian/control
echo -e '#!/usr/bin/make -f

%:
'"\t"'dh $@

override_dh_install:
'"\t"'mkdir -p $(CURDIR)/debian/'"$PKGBASE"'
'"\t"'cp -r $(CURDIR)/usr $(CURDIR)/debian/'"$PKGBASE"'/
' > debian/rules
chmod +x debian/rules
generate-changelog > debian/changelog

echo "Done. You can now build the package with 'cd $PKGBASE/$PKGBASE-$PKGVER && dpkg-buildpackage -us -uc'"

cd ../..
