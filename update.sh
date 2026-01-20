#!/bin/bash
set -e

echo "=========================================="
echo "Building aircraft database with UAV data"
echo "=========================================="
echo ""

function getGIT() {
    # getGIT $REPO $BRANCH $TARGET (directory)
    if [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]]; then echo "getGIT wrong usage, check your script or tell the author!" 1>&2; return 1; fi
    REPO="$1"; BRANCH="$2"; TARGET="$3"; pushd .
    if cd "$TARGET" &>/dev/null && git fetch --depth 1 origin "$BRANCH" && git reset --hard FETCH_HEAD; then popd; return 0; fi
    if ! cd /tmp || ! rm -rf "$TARGET"; then popd; return 1; fi
    if git clone --depth 1 --single-branch --branch "$2" "$1" "$3"; then popd; return 0; fi
    popd; return 1;
}

echo "[1/8] Downloading type longnames from GitHub..."
getGIT https://github.com/ADSBexchange/adsbx-type-longnames.git main "$(pwd)/longnames"
echo "  ✓ Type longnames downloaded"
echo ""

echo "[2/8] Downloading aircraft type definitions..."
wget -q --show-progress -O newTypes.json https://raw.githubusercontent.com/Mictronics/readsb-protobuf/dev/webapp/src/db/types.json
echo "  ✓ Type definitions downloaded"
echo ""

echo "[3/8] Merging UAV types into type definitions..."
if [ -f uav-types.json ]; then
    python3 -c "import json; types=json.load(open('newTypes.json')); uav=json.load(open('uav-types.json')); types.update(uav); json.dump(types, open('newTypes.json','w'), separators=(',',':'))"
    echo "  ✓ UAV types merged (MR4, MR6, FWU)"
else
    echo "  ⚠ uav-types.json not found, skipping UAV type merge"
fi
echo ""

echo "[4/8] Downloading Mictronics aircraft database..."
wget_result=0
wget --show-progress -O mic-db.zip https://www.mictronics.de/aircraft-database/indexedDB_old.php 2>&1 || wget_result=$?
if [ $wget_result -ne 0 ]; then
    echo "  ⚠ First attempt failed (exit code: $wget_result), trying with user agent..."
    wget --show-progress --user-agent="Mozilla/5.0" -O mic-db.zip https://www.mictronics.de/aircraft-database/indexedDB_old.php 2>&1 || wget_result=$?
    if [ $wget_result -ne 0 ]; then
        echo "  ✗ Failed to download Mictronics database (exit code: $wget_result)"
        echo "  This may be a temporary network issue. Please try again later."
        exit 1
    fi
fi
if [ ! -f mic-db.zip ] || [ ! -s mic-db.zip ]; then
    echo "  ✗ Downloaded file is empty or missing"
    exit 1
fi
echo "  ✓ Mictronics database downloaded ($(du -h mic-db.zip | cut -f1))"
echo ""

echo "[5/8] Extracting Mictronics database..."
unzip -o -q mic-db.zip
echo "  ✓ Database extracted"
echo ""

echo "[6/8] Downloading ADSBExchange basic aircraft database..."
wget -q --show-progress -O basic-ac-db.json.gz https://downloads.adsbexchange.com/downloads/basic-ac-db.json.gz
echo "  ✓ ADSBExchange database downloaded"
echo ""

echo "[7/8] Processing and merging databases..."
gunzip -c basic-ac-db.json.gz > basic-ac-db.json
sed -i.bak basic-ac-db.json \
    -e 's#\\\\.##g' \
    -e 's#\\.##g' \
    -e 's#\\##g'
echo "  ✓ Database files cleaned"

function compress() {
    rm -f "$1.gz"
    7za a -mx=9 "$1.gz" "$1"
}

echo "  Preparing database output directory..."
rm -f db/*
cp ranges.json db/ranges.js
cp airport-coords.json db/airport-coords.js
cp types.json db/icao_aircraft_types.js
cp newTypes.json db/icao_aircraft_types2.js
cp operators.json db/operators.js
echo "  ✓ Base files copied to db/"

echo "  Converting aircraft data format..."
sed -i -e 's/},/},\n/g' aircrafts.json
sed -e 's#\\u00c9#\xc3\x89#g' \
    -e 's#\\u00e9#\xc3\xa9#g' \
    -e 's#\\/#/#g' \
    -e "s/''/'/g" \
    aircrafts.json > aircraftUtf.json

perl -i -pe 's/\\u00(..)/chr(hex($1))/eg' aircraftUtf.json
echo "  ✓ UTF-8 encoding fixed"

echo "  Running toJson.py to merge all data sources (including UAVs)..."
./toJson.py aircraftUtf.json db newTypes.json basic-ac-db.json
echo "  ✓ Database merge complete (regular aircraft + UAVs)"

echo "  Finalizing aircraft.csv..."
sed -i -e 's/\\;/,/' aircraft.csv
echo "  ✓ aircraft.csv generated"

echo "  Compressing database files..."
for file in db/*; do
    compress "$file"
    mv "$file.gz" "$file"
done
echo "  ✓ Database files compressed"
echo ""

echo "[8/8] Build complete!"
echo ""
echo "=========================================="
echo "Generated files:"
echo "  - aircraft.csv.gz (for readsb --db-file)"
echo "  - db/*.js (compressed client-side database)"
echo "  - db/icao_aircraft_types2.js (includes UAV types)"
echo "=========================================="
echo ""

# Git operations commented out for local development
# Uncomment these lines if you want to commit and push to the remote repository
# git add db
# git commit --amend --date "$(date)" -m "database update (to keep the repository small, this commit is replaced regularly)"
# git push -f
