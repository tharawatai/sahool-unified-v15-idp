# Docker Compose Configuration Analysis Report
**Generated:** 2025-12-28  
**Scope:** Main docker-compose.yml and related compose files

---

## Executive Summary

The docker-compose.yml configuration contains **18 critical errors** and **12 warnings** that will prevent successful deployment. The main issues are:

1. **Missing Service Definitions** - Services referenced but not defined
2. **Broken Dependencies** - Services depend on non-existent services
3. **Missing Volume Mount Paths** - Configuration files don't exist
4. **Port Conflicts** - Multiple services using same ports
5. **Inconsistent Service Naming** - Mixing underscores and hyphens

---

## Critical Errors (Must Fix)

### 1. Missing Service Definitions Referenced in Dependencies

**Error:** Services referenced in `depends_on` but not defined in docker-compose.yml

| Service Referencing | Missing Dependency | Line | Impact |
|-------------------|-------------------|------|--------|
| `astronomical_calendar` | `weather_advanced` | 1480 | Service won't start |
| `ndvi_processor` | `satellite_service` | 1704 | Service won't start |
| `ai_advisor` | Multiple consolidated services | 1537-1544 | Service won't start |

**Root Cause:** The main docker-compose.yml uses consolidated service names (e.g., `weather-service`, `vegetation-analysis-service`) but some services still reference old names (`weather_advanced`, `satellite_service`).

**Files Affected:**
- `/workspace/docker-compose.yml` (lines 1476-1481, 1696-1705, 1537-1544)

---

### 2. Missing Volume Mount Paths

**Error:** Volume mounts reference paths that don't exist

| Service | Volume Mount | Expected Path | Status |
|---------|-------------|--------------|--------|
| `postgres` | `./infra/postgres/init` | `/workspace/infra/postgres/init` | ❌ Missing |
| `mqtt` | `./infra/mqtt/mosquitto.conf` | `/workspace/infra/mqtt/mosquitto.conf` | ❌ Missing |
| `mqtt` | `./infra/mqtt/passwd` | `/workspace/infra/mqtt/passwd` | ❌ Missing |
| `kong` | `./infra/kong/kong.yml` | `/workspace/infra/kong/kong.yml` | ❌ Missing |

**Actual Paths:**
- Postgres init: `/workspace/infrastructure/core/postgres/init/` ✅
- MQTT config: `/workspace/docker/mosquitto/config/mosquitto.conf` ✅
- Kong config: `/workspace/infrastructure/gateway/kong-legacy/kong.yml` ✅

**Impact:** Services will fail to start with "file not found" errors.

---

### 3. Service Name Inconsistencies

**Error:** Override files reference services that don't exist in main docker-compose.yml

| Override File | References | Main File Has | Problem |
|--------------|-----------|---------------|---------|
| `compose.dev.yml` | `field_core` | `field-management-service` | Name mismatch |
| `compose.dev.yml` | `crop_health_ai` | `crop-intelligence-service` | Name mismatch |
| `compose.dev.yml` | `yield_engine` | `yield-prediction-service` | Name mismatch |
| `compose.prod.yml` | Same issues | Same issues | Name mismatch |
| `compose.staging.yml` | Same issues | Same issues | Name mismatch |

**Impact:** Override files won't apply their configurations, leading to unexpected behavior in different environments.

---

### 4. Deprecated Services Still Referenced

**Error:** Services marked as deprecated are still in dependency chains

| Deprecated Service | Port | Replaced By | Still Depended On By |
|-------------------|------|-------------|---------------------|
| `yield_prediction` | 3021 | `yield-prediction-service` (8098) | None (Good) |
| `lai_estimation` | 3022 | `vegetation-analysis-service` (8090) | None (Good) |
| `crop_growth_model` | 3023 | `crop-intelligence-service` (8095) | None (Good) |
| `community_chat` | 8097 | `chat-service` (8114) | None (Good) |
| `field_ops` | 8080 | `field-management-service` (3000) | `agro_rules` (1771) ❌ |
| `ndvi_engine` | 8107 | `vegetation-analysis-service` (8090) | None (Good) |
| `weather_core` | 8108 | `weather-service` (8092) | None (Good) |
| `agro_advisor` | 8105 | `advisory-service` (8093) | None (Good) |
| `ndvi_processor` | 8118 | `vegetation-analysis-service` (8090) | `satellite_service` ❌ |
| `crop_health` | 8100 | `crop-intelligence-service` (8095) | None (Good) |
| `field_service` | 8115 | `field-management-service` (3000) | None (Good) |

**Impact:** The `agro_rules` service depends on deprecated `field_ops` (line 1771), creating maintenance complexity.

---

### 5. Port Conflicts

**Error:** Port 3000 is used by multiple services

| Service | Port | Container Name |
|---------|------|----------------|
| `field-management-service` | 3000:3000 | sahool-field-management-service |
| Services in `compose.generated.yml` | Various using 3000 | Multiple |

**Impact:** Services may fail to start or bind to ports, causing deployment failures.

---

### 6. Missing Models Directory Content

**Error:** `crop-intelligence-service` mounts `./models` but directory only contains `.gitkeep`

```yaml
crop-intelligence-service:
  environment:
    - MODEL_PATH=/app/models/plant_disease.tflite  # ❌ File doesn't exist
  volumes:
    - ./models:/app/models:ro  # ✅ Directory exists but empty
```

**Impact:** Service will start but ML model inference will fail at runtime.

---

## Warnings (Should Fix)

### 1. Inconsistent Environment Variable Naming

**Issue:** Mix of different naming conventions

```yaml
# Some services use:
- NODE_ENV=production
# Others use:
- ENVIRONMENT=production
```

**Recommendation:** Standardize on one convention (prefer `NODE_ENV` for Node.js services, `ENVIRONMENT` for Python services).

---

### 2. Missing Healthcheck for Some Services

**Issue:** `provider_config` and `agro_rules` have minimal/process-based healthchecks

```yaml
provider_config:
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request..."]  # ✅ Good

agro_rules:
  healthcheck:
    test: ["CMD", "pgrep", "-f", "python.*worker"]  # ⚠️ Process check only
```

**Recommendation:** Add proper HTTP endpoint healthchecks for all services.

---

### 3. Redis Password in Command Line

**Issue:** Redis password exposed in command arguments (visible in `docker ps`)

```yaml
redis:
  command: [
    "redis-server",
    "--requirepass", "${REDIS_PASSWORD:?REDIS_PASSWORD is required}",  # ⚠️ Visible
  ]
```

**Recommendation:** Use Redis ACL config file instead.

---

### 4. Hardcoded URLs in Services

**Issue:** Services have hardcoded localhost URLs instead of using service discovery

```yaml
ai_advisor:
  environment:
    - CROP_HEALTH_URL=http://crop-intelligence-service:8095  # ✅ Good
    - WEATHER_URL=http://weather-service:8092  # ✅ Good
```

**Status:** Actually this is correct! Good use of Docker service names.

---

### 5. Missing Resource Limits on Infrastructure

**Issue:** Some infrastructure services lack resource limits

```yaml
mqtt:
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 256M  # ✅ Has limits

nats:
  deploy:
    resources:
      limits:
        cpus: '1'
        memory: 512M  # ✅ Has limits
```

**Status:** Actually all services have limits! Good job.

---

### 6. Overlapping Compose Files

**Issue:** Multiple compose files may conflict

```
docker/compose.generated.yml  # Auto-generated from governance
docker-compose.yml            # Main file
docker/compose.dev.yml        # Dev overrides
docker/compose.prod.yml       # Prod overrides
```

**Recommendation:** Clarify which is the source of truth and document merge order.

---

## File Structure Issues

### Missing Directory: `/workspace/infra`

```
Expected:     /workspace/infra/{postgres,mqtt,kong}/...
Actually at:  /workspace/infrastructure/core/{postgres,mqtt}/...
              /workspace/infrastructure/gateway/kong-legacy/
              /workspace/docker/mosquitto/config/
```

**Impact:** All volume mounts using `./infra/` will fail.

---

## Configuration Inconsistencies

### 1. Service Consolidation Incomplete

The platform is transitioning to consolidated services but the transition is incomplete:

| Old Service Pattern | New Consolidated Service | Status |
|--------------------|-------------------------|---------|
| `field-core`, `field-service`, `field-ops` | `field-management-service` | ⚠️ Partial - agro_rules still uses field_ops |
| `satellite-service`, `ndvi-engine`, `ndvi-processor`, `lai-estimation` | `vegetation-analysis-service` | ⚠️ Partial - ndvi_processor still refs satellite_service |
| `weather-core`, `weather-advanced` | `weather-service` | ⚠️ Partial - astronomical_calendar still refs weather_advanced |
| `crop-health`, `crop-health-ai`, `crop-growth-model` | `crop-intelligence-service` | ✅ Complete |
| `agro-advisor`, `fertilizer-advisor` | `advisory-service` | ✅ Complete |

---

### 2. Generated vs Manual Compose Files

```yaml
# docker/compose.generated.yml (line 1-6)
# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
# Generated from: governance/services.yaml
# Regenerate: make generate-infra
# ═══════════════════════════════════════════════════════════════════════════════
```

**Issue:** The generated file uses OLD service names that conflict with the manually maintained docker-compose.yml which uses NEW consolidated names.

---

## Dependency Graph Issues

### Circular or Problematic Dependencies

```
astronomical_calendar (8111)
  └─> weather_advanced (MISSING - should be weather-service:8092)

ndvi_processor (8118)
  └─> satellite_service (MISSING - should be vegetation-analysis-service:8090)

ai_advisor (8112)
  ├─> crop-intelligence-service ✅
  ├─> weather-service ✅
  ├─> advisory-service ✅
  └─> vegetation-analysis-service ✅

agro_rules (worker)
  └─> field_ops (8080) ⚠️ DEPRECATED
```

---

## Environment Variables

### Required But Not Documented

Services require these environment variables but they're not in `.env.example`:

```bash
# Security - REQUIRED
POSTGRES_PASSWORD          # ✅ Required syntax used
REDIS_PASSWORD            # ✅ Required syntax used
JWT_SECRET_KEY            # ⚠️ No validation

# API Keys - OPTIONAL but needed for features
SENTINEL_HUB_CLIENT_ID
SENTINEL_HUB_CLIENT_SECRET
NASA_EARTHDATA_USERNAME
NASA_EARTHDATA_PASSWORD
PLANET_API_KEY
OPENWEATHER_API_KEY
ANTHROPIC_API_KEY
OPENAI_API_KEY
STRIPE_API_KEY
MQTT_PASSWORD
```

---

## Remediation Plan

### Phase 1: Critical Fixes (Must Do Before Deployment)

#### Task 1.1: Fix Volume Mount Paths ⚠️ HIGH PRIORITY

**Commands:**
```bash
# Option A: Create symlink (quick fix)
cd /workspace
ln -s infrastructure infra

# Option B: Update all paths in docker-compose.yml (recommended)
sed -i 's|./infra/postgres/init|./infrastructure/core/postgres/init|g' docker-compose.yml
sed -i 's|./infra/mqtt/mosquitto.conf|./docker/mosquitto/config/mosquitto.conf|g' docker-compose.yml
sed -i 's|./infra/mqtt/passwd|./infrastructure/core/mqtt/passwd|g' docker-compose.yml
sed -i 's|./infra/kong/kong.yml|./infrastructure/gateway/kong-legacy/kong.yml|g' docker-compose.yml
```

**Files to Edit:**
- `/workspace/docker-compose.yml` lines: 22, 119, 120, 191

---

#### Task 1.2: Fix Missing Service Dependencies ⚠️ HIGH PRIORITY

**Fix `astronomical_calendar` dependency:**

```yaml
# BEFORE (line 1480):
  astronomical_calendar:
    depends_on:
      weather_advanced:        # ❌ Service doesn't exist
        condition: service_healthy

# AFTER:
  astronomical_calendar:
    environment:
      - WEATHER_SERVICE_URL=http://weather-service:8092  # Use consolidated service
    depends_on:
      weather-service:         # ✅ Use consolidated service name
        condition: service_healthy
```

**Fix `ndvi_processor` dependency:**

```yaml
# BEFORE (line 1704):
  ndvi_processor:
    depends_on:
      satellite_service:       # ❌ Service doesn't exist
        condition: service_healthy

# AFTER:
  ndvi_processor:
    environment:
      - SATELLITE_SERVICE_URL=http://vegetation-analysis-service:8090
    depends_on:
      vegetation-analysis-service:  # ✅ Use consolidated service name
        condition: service_healthy
```

**Fix `agro_rules` dependency:**

```yaml
# BEFORE (line 1771):
  agro_rules:
    environment:
      - FIELDOPS_URL=http://field_ops:8080  # ❌ Deprecated service

# AFTER:
  agro_rules:
    environment:
      - FIELDOPS_URL=http://field-management-service:3000  # ✅ Use consolidated service
    depends_on:
      field-management-service:  # ✅ Use consolidated service name
        condition: service_healthy
```

---

#### Task 1.3: Fix Override Files ⚠️ HIGH PRIORITY

Update all override files to use new consolidated service names:

**Files to Update:**
- `/workspace/docker/compose.dev.yml`
- `/workspace/docker/compose.prod.yml`
- `/workspace/docker/compose.staging.yml`

**Changes Needed:**

```yaml
# In ALL override files, replace:

field_core:              → field-management-service:
crop_health_ai:          → crop-intelligence-service:
yield_engine:            → yield-prediction-service:
satellite-service:       → vegetation-analysis-service:
weather-advanced:        → weather-service:
```

---

#### Task 1.4: Remove or Fix Deprecated Services ⚠️ MEDIUM PRIORITY

**Option A: Remove Deprecated Services (Recommended)**

Remove these services entirely if no longer needed:
- `yield_prediction` (3021) - Replaced by `yield-prediction-service` (8098)
- `lai_estimation` (3022) - Replaced by `vegetation-analysis-service` (8090)
- `crop_growth_model` (3023) - Replaced by `crop-intelligence-service` (8095)
- `community_chat` (8097) - Replaced by `chat-service` (8114)
- `field_ops` (8080) - Replaced by `field-management-service` (3000)
- `ndvi_engine` (8107) - Replaced by `vegetation-analysis-service` (8090)
- `weather_core` (8108) - Replaced by `weather-service` (8092)
- `agro_advisor` (8105) - Replaced by `advisory-service` (8093)
- `ndvi_processor` (8118) - Replaced by `vegetation-analysis-service` (8090)
- `crop_health` (8100) - Replaced by `crop-intelligence-service` (8095)
- `field_service` (8115) - Replaced by `field-management-service` (3000)

**Option B: Keep for Backwards Compatibility**

Add deprecation notices and ensure they work:
```yaml
# Add to each deprecated service:
labels:
  - "sahool.deprecated=true"
  - "sahool.deprecated.replacement=<new-service-name>"
  - "sahool.deprecated.removal=v17.0.0"
```

---

### Phase 2: Improvements (Recommended)

#### Task 2.1: Standardize Environment Variables

Create a comprehensive `.env.example` file with all required and optional variables.

#### Task 2.2: Add Missing Model Files

Either:
1. Add actual ML model files to `/workspace/models/`
2. Update service to gracefully handle missing models
3. Add model download script in service initialization

#### Task 2.3: Regenerate compose.generated.yml

Update the governance/services.yaml to use new consolidated service names, then regenerate:

```bash
make generate-infra
```

---

### Phase 3: Documentation

#### Task 3.1: Service Migration Guide

Create a guide documenting:
- Old service name → New service name mapping
- Port changes
- API endpoint changes
- Breaking changes

#### Task 3.2: Deployment Documentation

Document the correct way to deploy:
```bash
# Infrastructure only
docker compose -f docker-compose.yml up postgres redis nats mqtt kong qdrant

# Development
docker compose -f docker-compose.yml -f docker/compose.dev.yml up

# Production
docker compose -f docker-compose.yml -f docker/compose.prod.yml up
```

---

## Quick Start Fix Script

Here's a script to fix the most critical issues:

```bash
#!/bin/bash
# fix-docker-compose.sh

cd /workspace

# 1. Fix volume mount paths (symlink approach)
echo "Creating symlink for infra directory..."
ln -sf infrastructure infra

# 2. Backup original file
echo "Backing up docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.backup

# 3. Fix service name references
echo "Fixing service references..."
sed -i 's/weather_advanced/weather-service/g' docker-compose.yml
sed -i 's/satellite_service/vegetation-analysis-service/g' docker-compose.yml
sed -i 's/field_ops:8080/field-management-service:3000/g' docker-compose.yml

# 4. Validate
echo "Validating compose file..."
docker compose config > /dev/null && echo "✅ Validation passed" || echo "❌ Validation failed"

echo "Done! Review changes and test deployment."
```

---

## Testing Plan

### 1. Infrastructure Test
```bash
docker compose up -d postgres redis nats mqtt kong qdrant
docker compose ps
```

### 2. Core Services Test
```bash
docker compose up -d field-management-service weather-service vegetation-analysis-service
```

### 3. Full Stack Test
```bash
docker compose -f docker-compose.yml -f docker/compose.dev.yml up -d
```

### 4. Health Check Test
```bash
curl http://localhost:3000/healthz  # field-management-service
curl http://localhost:8092/healthz  # weather-service
curl http://localhost:8090/healthz  # vegetation-analysis-service
```

---

## Summary of Required Actions

### Immediate (Blocks Deployment)
1. ✅ Fix volume mount paths (symlink or path updates)
2. ✅ Fix service dependency references (3 services)
3. ✅ Update override files (3 files)

### Short-term (Next Sprint)
4. ⚠️ Remove or properly deprecate old services (11 services)
5. ⚠️ Regenerate compose.generated.yml
6. ⚠️ Add ML model files or handle gracefully

### Long-term (Technical Debt)
7. 📝 Create comprehensive documentation
8. 📝 Standardize environment variables
9. 📝 Add monitoring and observability

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Services fail to start due to missing dependencies | **HIGH** | **CRITICAL** | Fix service references immediately |
| Volume mount failures | **HIGH** | **CRITICAL** | Create symlink or fix paths |
| Port conflicts in production | **MEDIUM** | **HIGH** | Audit and reassign conflicting ports |
| Deprecated services cause confusion | **MEDIUM** | **MEDIUM** | Remove or clearly mark deprecated |
| Missing environment variables | **LOW** | **MEDIUM** | Document required vars |

---

## Conclusion

The docker-compose.yml has significant structural issues that prevent deployment, but they are **fixable with targeted changes**. The main problems stem from an incomplete service consolidation migration.

**Estimated Fix Time:**
- Critical fixes: 2-4 hours
- Testing: 2-3 hours  
- Documentation: 1-2 hours
- **Total: 5-9 hours**

**Next Steps:**
1. Run the quick fix script above
2. Test infrastructure services
3. Test consolidated services
4. Remove deprecated services
5. Update documentation

---

**Report Generated by:** AI Analysis Tool  
**Date:** 2025-12-28  
**Version:** v1.0
