#!/bin/bash
set -e

echo "=========================================="
echo "Building UAV-only database (minimal)"
echo "=========================================="
echo ""

# Create minimal types file with just UAV types
echo "[1/4] Creating UAV type definitions..."
mkdir -p db
cat > db/icao_aircraft_types2.js << 'EOF'
{
  "MR4": ["Multi-Rotor Quadcopter", "MR4", "L"],
  "MR6": ["Multi-Rotor Hexacopter", "MR6", "L"],
  "FWU": ["Fixed-Wing UAV", "FWU", "L"]
}
EOF
echo "  ✓ UAV types created"
echo ""

# Create minimal aircraft.csv with just UAV entries
echo "[2/4] Generating aircraft.csv with UAV entries..."
if [ ! -f uav-database.json ]; then
    echo "  ✗ uav-database.json not found!"
    exit 1
fi

# Create CSV with UAV entries (add padding to meet readsb's 1000 byte minimum)
python3 << 'PYEOF'
import json
import csv

# Read UAV database
uavs = []
with open('uav-database.json', 'r') as f:
    for line in f:
        if line.strip():
            uavs.append(json.loads(line))

# Write CSV entries
with open('aircraft.csv', 'w', newline='', encoding='utf-8') as csvfile:
    writer = csv.writer(csvfile, delimiter=';', quoting=csv.QUOTE_NONE, escapechar='\\', lineterminator='\n')
    
    # Add comment header to increase file size
    csvfile.write("# UAV-only database - minimal build for testing\n")
    csvfile.write("# Format: ICAO;Registration;Type;Flags;Description;Year;Owner;\n")
    csvfile.write("# This file contains only UAV entries for local development\n")
    csvfile.write("# " + "=" * 100 + "\n")
    
    # Write UAV entries
    for uav in sorted(uavs, key=lambda x: x['icao']):
        icao = uav['icao'].upper()
        reg = uav.get('reg', '')
        icaotype = uav.get('icaotype', '')
        flags = '00001'
        desc = ''
        year = uav.get('year', '')
        ownop = uav.get('ownop', '')
        writer.writerow([icao, reg, icaotype, flags, desc, year, ownop, ''])

print(f"  ✓ Added {len(uavs)} UAV entries to aircraft.csv")
PYEOF

# Ensure file is at least 1000 bytes (readsb requirement)
file_size=$(wc -c < aircraft.csv | tr -d ' ')
if [ $file_size -lt 1000 ]; then
    echo "  ⚠ File is only $file_size bytes, adding padding to meet 1000 byte minimum..."
    # Add comment padding
    padding_needed=$((1000 - file_size + 50))
    printf "# %*s\n" $padding_needed "" >> aircraft.csv
    echo "  ✓ Padding added"
fi

echo "  ✓ aircraft.csv generated"
echo ""

# Compress the CSV
echo "[3/4] Compressing aircraft.csv..."
gzip -f -k aircraft.csv
echo "  ✓ aircraft.csv.gz created"
echo ""

# Create minimal db files for client-side lookup
echo "[4/4] Creating client-side database files..."
python3 << 'PYEOF'
import json
import os

# Read UAV database
uavs = []
with open('uav-database.json', 'r') as f:
    for line in f:
        if line.strip():
            uavs.append(json.loads(line))

# Create blocks structure (simplified - just put all in block '0')
blocks = {'0': {}}
for uav in uavs:
    icao = uav['icao'].upper()
    if len(icao) == 6:
        # Format: [registration, type, flags, description, country, country_code]
        blocks['0'][icao[1:]] = [
            uav.get('reg', ''),
            uav.get('icaotype', ''),
            '00001',
            '',
            uav.get('country', ''),
            uav.get('country_code', '')
        ]

# Write block files
os.makedirs('db', exist_ok=True)
for bkey, blockdata in blocks.items():
    with open(f'db/{bkey}.js', 'w', encoding='utf-8') as f:
        json.dump(blockdata, f, check_circular=False, separators=(',',':'), sort_keys=True)

# Write files.js
with open('db/files.js', 'w', encoding='utf-8') as f:
    json.dump(list(blocks.keys()), f, check_circular=False, separators=(',',':'), sort_keys=True)

print(f"  ✓ Created db/0.js with {len(uavs)} UAV entries")
PYEOF

echo "  ✓ Client-side database files created"
echo ""

echo "=========================================="
echo "Build complete!"
echo ""
echo "Generated files:"
echo "  - aircraft.csv.gz (UAV entries only)"
echo "  - db/0.js (client-side database)"
echo "  - db/icao_aircraft_types2.js (UAV types)"
echo "=========================================="
echo ""
