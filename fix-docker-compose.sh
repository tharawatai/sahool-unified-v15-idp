#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Docker Compose Fix Script for SAHOOL v16.0.0
# Fixes critical issues preventing deployment
# ═══════════════════════════════════════════════════════════════════════════════

set -e  # Exit on error

WORKSPACE_DIR="/workspace"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SAHOOL Docker Compose Fix Script${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Change to workspace directory
cd "$WORKSPACE_DIR" || exit 1

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Backup original files
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[1/6] Backing up original files...${NC}"

files_to_backup=(
    "docker-compose.yml"
    "docker/compose.dev.yml"
    "docker/compose.prod.yml"
    "docker/compose.staging.yml"
)

for file in "${files_to_backup[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "${file}${BACKUP_SUFFIX}"
        echo "  ✓ Backed up: $file → ${file}${BACKUP_SUFFIX}"
    else
        echo -e "  ${RED}✗ File not found: $file${NC}"
    fi
done

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Fix volume mount paths in main docker-compose.yml
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/6] Fixing volume mount paths...${NC}"

# Option: Create symlink (quick fix)
if [ ! -e "$WORKSPACE_DIR/infra" ]; then
    ln -sf infrastructure infra
    echo "  ✓ Created symlink: infra → infrastructure"
else
    echo "  ℹ Symlink already exists: infra"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Fix service dependency references in main docker-compose.yml
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[3/6] Fixing service dependency references...${NC}"

# Fix astronomical_calendar dependency: weather_advanced → weather-service
if grep -q "weather_advanced:" docker-compose.yml; then
    sed -i 's/weather_advanced:/weather-service:/g' docker-compose.yml
    echo "  ✓ Fixed: weather_advanced → weather-service"
fi

# Fix ndvi_processor dependency: satellite_service → vegetation-analysis-service
if grep -q "satellite_service:" docker-compose.yml; then
    sed -i 's/satellite_service:/vegetation-analysis-service:/g' docker-compose.yml
    echo "  ✓ Fixed: satellite_service → vegetation-analysis-service"
fi

# Fix agro_rules environment variable: field_ops:8080 → field-management-service:3000
if grep -q "field_ops:8080" docker-compose.yml; then
    sed -i 's|http://field_ops:8080|http://field-management-service:3000|g' docker-compose.yml
    echo "  ✓ Fixed: field_ops:8080 → field-management-service:3000"
fi

# Fix URL environment variables
sed -i 's|http://weather_advanced:|http://weather-service:|g' docker-compose.yml
sed -i 's|http://satellite_service:|http://vegetation-analysis-service:|g' docker-compose.yml

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Fix service names in override files
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[4/6] Fixing service names in override files...${NC}"

override_files=(
    "docker/compose.dev.yml"
    "docker/compose.prod.yml"
    "docker/compose.staging.yml"
)

service_replacements=(
    "field_core:field-management-service:"
    "crop_health_ai:crop-intelligence-service:"
    "yield_engine:yield-prediction-service:"
)

for file in "${override_files[@]}"; do
    if [ -f "$file" ]; then
        echo "  Processing: $file"
        for replacement in "${service_replacements[@]}"; do
            old_name=$(echo "$replacement" | cut -d: -f1)
            new_name=$(echo "$replacement" | cut -d: -f2)
            
            # Check if the old service name exists as a top-level service definition
            if grep -q "^  ${old_name}:" "$file"; then
                sed -i "s/^  ${old_name}:/  ${new_name}:/g" "$file"
                echo "    ✓ Replaced: $old_name → $new_name"
            fi
        done
    fi
done

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Add deprecation warnings to deprecated services
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[5/6] Adding deprecation labels to old services...${NC}"

# This is a complex transformation, so we'll create a Python script to do it
cat > /tmp/add_deprecation_labels.py << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
import sys
import re

deprecated_services = {
    'yield_prediction': 'yield-prediction-service',
    'lai_estimation': 'vegetation-analysis-service',
    'crop_growth_model': 'crop-intelligence-service',
    'community_chat': 'chat-service',
    'field_ops': 'field-management-service',
    'ndvi_engine': 'vegetation-analysis-service',
    'weather_core': 'weather-service',
    'agro_advisor': 'advisory-service',
    'ndvi_processor': 'vegetation-analysis-service',
    'crop_health': 'crop-intelligence-service',
    'field_service': 'field-management-service',
}

def add_labels_to_service(content, service_name, replacement):
    """Add deprecation labels to a service if not already present."""
    # Find the service definition
    service_pattern = rf'^  {service_name}:\s*$'
    
    lines = content.split('\n')
    modified = False
    new_lines = []
    in_target_service = False
    labels_added = False
    
    for i, line in enumerate(lines):
        if re.match(service_pattern, line):
            in_target_service = True
            labels_added = False
        elif in_target_service and line.strip() and not line.startswith('  '):
            # End of service definition
            in_target_service = False
        
        # Add labels after the service name line if not already present
        if in_target_service and not labels_added:
            # Check if labels section already exists
            if i + 1 < len(lines) and 'labels:' not in lines[i+1]:
                # Look for where to insert (after ports or environment)
                if 'ports:' in line or 'environment:' in line:
                    new_lines.append(line)
                    # Skip to end of the current section
                    continue
            elif 'sahool.deprecated' not in ''.join(lines[i:i+10]):
                # Add labels if not already present
                if 'networks:' in line:
                    # Insert before networks
                    new_lines.append('    labels:')
                    new_lines.append('      - "sahool.deprecated=true"')
                    new_lines.append(f'      - "sahool.replacement={replacement}"')
                    new_lines.append('      - "sahool.removal-version=v17.0.0"')
                    labels_added = True
                    modified = True
        
        new_lines.append(line)
    
    return '\n'.join(new_lines) if modified else content

# Read input
if len(sys.argv) > 1:
    with open(sys.argv[1], 'r') as f:
        content = f.read()
else:
    content = sys.stdin.read()

# Process each deprecated service
for service, replacement in deprecated_services.items():
    if f'  {service}:' in content:
        content = add_labels_to_service(content, service, replacement)
        print(f"Processed: {service}", file=sys.stderr)

# Write output
if len(sys.argv) > 1:
    with open(sys.argv[1], 'w') as f:
        f.write(content)
else:
    print(content)
PYTHON_SCRIPT

chmod +x /tmp/add_deprecation_labels.py

# Run the Python script (if Python is available)
if command -v python3 &> /dev/null; then
    python3 /tmp/add_deprecation_labels.py docker-compose.yml 2>&1 | grep "Processed:" || echo "  ℹ No deprecated services to label"
else
    echo "  ⚠ Python3 not found, skipping deprecation labels"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Validate the fixed configuration
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[6/6] Validating configuration...${NC}"

# Check if docker or docker-compose is available
if command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
        echo "  ℹ Using 'docker compose' (Docker Compose V2)"
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "  ℹ Using 'docker-compose' (Docker Compose V1)"
        COMPOSE_CMD="docker-compose"
    else
        echo -e "  ${RED}✗ docker-compose not found, cannot validate${NC}"
        COMPOSE_CMD=""
    fi
    
    if [ -n "$COMPOSE_CMD" ]; then
        echo "  Validating docker-compose.yml..."
        if $COMPOSE_CMD -f docker-compose.yml config > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Main compose file is valid${NC}"
        else
            echo -e "  ${RED}✗ Main compose file has errors:${NC}"
            $COMPOSE_CMD -f docker-compose.yml config 2>&1 | head -10
        fi
        
        echo "  Validating with dev overrides..."
        if $COMPOSE_CMD -f docker-compose.yml -f docker/compose.dev.yml config > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Dev configuration is valid${NC}"
        else
            echo -e "  ${YELLOW}⚠ Dev configuration has warnings${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}⚠ Docker not found, skipping validation${NC}"
    echo "  Run 'docker compose config' manually to validate"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Fix Script Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Review the changes:"
echo "   git diff docker-compose.yml"
echo ""
echo "2. Test infrastructure services:"
echo "   docker compose up -d postgres redis nats mqtt kong"
echo ""
echo "3. Test core services:"
echo "   docker compose up -d field-management-service weather-service"
echo ""
echo "4. Full deployment:"
echo "   docker compose -f docker-compose.yml -f docker/compose.dev.yml up -d"
echo ""
echo -e "${YELLOW}Backup files created:${NC}"
for file in "${files_to_backup[@]}"; do
    if [ -f "${file}${BACKUP_SUFFIX}" ]; then
        echo "  - ${file}${BACKUP_SUFFIX}"
    fi
done
echo ""
echo -e "${BLUE}To restore backups if needed:${NC}"
echo "  mv docker-compose.yml${BACKUP_SUFFIX} docker-compose.yml"
echo ""
echo "For detailed analysis, see: /workspace/DOCKER_COMPOSE_ANALYSIS.md"
echo ""
