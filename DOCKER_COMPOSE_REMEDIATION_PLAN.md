# Docker Compose Remediation Plan
**SAHOOL v16.0.0 - Production Readiness Checklist**

---

## Phase 1: Immediate Critical Fixes (Required Before Deployment)

### Priority: 🔴 CRITICAL | Timeline: 1-2 hours

#### Task 1.1: Fix Volume Mount Paths
**Issue:** Volume mounts point to non-existent `/workspace/infra` directory

**Solution:**
```bash
cd /workspace
ln -sf infrastructure infra
```

**Verification:**
```bash
ls -la infra/  # Should show infrastructure contents
docker compose config | grep -A2 "volumes:" | grep infra
```

**Files Modified:**
- Creates symlink: `/workspace/infra -> /workspace/infrastructure`

---

#### Task 1.2: Fix Missing Service Dependencies
**Issue:** Services depend on old service names that don't exist

**Solution:** Update service references in `/workspace/docker-compose.yml`

**Changes Required:**

1. **astronomical_calendar (line ~1480):**
```yaml
# BEFORE:
depends_on:
  weather_advanced:
    condition: service_healthy

# AFTER:
depends_on:
  weather-service:
    condition: service_healthy
```

2. **ndvi_processor (line ~1704):**
```yaml
# BEFORE:  
depends_on:
  satellite_service:
    condition: service_healthy

# AFTER:
depends_on:
  vegetation-analysis-service:
    condition: service_healthy
```

3. **agro_rules (line ~1766):**
```yaml
# BEFORE:
environment:
  - FIELDOPS_URL=http://field_ops:8080

# AFTER:
environment:
  - FIELDOPS_URL=http://field-management-service:3000

depends_on:
  field-management-service:
    condition: service_healthy
```

**Automated Fix:**
```bash
./fix-docker-compose.sh
```

**Verification:**
```bash
docker compose config | grep -E "weather_advanced|satellite_service|field_ops:8080"
# Should return empty
```

---

#### Task 1.3: Fix Override Files
**Issue:** Override files (dev/prod/staging) reference non-existent service names

**Solution:** Update service names in all 3 override files

**Files to Modify:**
1. `/workspace/docker/compose.dev.yml`
2. `/workspace/docker/compose.prod.yml`
3. `/workspace/docker/compose.staging.yml`

**Changes in Each File:**
```yaml
# BEFORE:
field_core:
  environment: ...
  
crop_health_ai:
  environment: ...
  
yield_engine:
  environment: ...

# AFTER:
field-management-service:
  environment: ...
  
crop-intelligence-service:
  environment: ...
  
yield-prediction-service:
  environment: ...
```

**Automated Fix:**
```bash
./fix-docker-compose.sh
```

**Verification:**
```bash
docker compose -f docker-compose.yml -f docker/compose.dev.yml config > /dev/null
echo $?  # Should be 0
```

---

### Testing After Phase 1

```bash
# 1. Validate configuration
docker compose config > /dev/null && echo "✅ Valid" || echo "❌ Invalid"

# 2. Start infrastructure
docker compose up -d postgres redis nats mqtt kong qdrant

# 3. Wait for healthy
sleep 30

# 4. Check health
docker compose ps | grep -v "healthy" | grep -v "NAME"

# 5. Start core services
docker compose up -d \
  field-management-service \
  weather-service \
  vegetation-analysis-service \
  crop-intelligence-service \
  advisory-service

# 6. Check logs for errors
docker compose logs --tail=50 | grep -i error
```

**Expected Result:** All services start without dependency errors

---

## Phase 2: Service Cleanup (Recommended for Production)

### Priority: 🟡 HIGH | Timeline: 4-6 hours

#### Task 2.1: Remove Deprecated Services

**Decision Required:** Keep deprecated services for backwards compatibility OR remove completely?

**Option A: Remove Completely (Recommended)**

Services to remove from `/workspace/docker-compose.yml`:
1. `yield_prediction` (line 391-431)
2. `lai_estimation` (line 436-476)
3. `crop_growth_model` (line 481-521)
4. `community_chat` (line 614-651)
5. `field_ops` (line 660-699)
6. `ndvi_engine` (line 1337-1373)
7. `weather_core` (line 1378-1418)
8. `agro_advisor` (line 1250-1286)
9. `ndvi_processor` (line 1685-1722)
10. `crop_health` (line 1727-1755)
11. `field_service` (line 1606-1643)

**Impact:**
- ✅ Reduces complexity
- ✅ Frees resources
- ✅ Clearer architecture
- ❌ Breaks old API clients (if any)

**Migration Path:**
```yaml
# Add deprecation notice to Kong routes
# Redirect old endpoints to new services
# Log deprecation warnings for 2 weeks
# Remove after grace period
```

---

**Option B: Keep with Deprecation Labels**

Add labels to each deprecated service:
```yaml
labels:
  - "sahool.deprecated=true"
  - "sahool.replacement=<new-service-name>"
  - "sahool.removal-version=v17.0.0"
```

**Automated Fix:**
```bash
./fix-docker-compose.sh  # Includes deprecation labeling
```

---

#### Task 2.2: Resolve Port Conflicts

**Issue:** Multiple services may try to use port 3000

**Investigation Required:**
```bash
# Check for port conflicts
grep -n "ports:" docker-compose.yml | grep "3000:"
```

**Resolution:**
- Audit all port assignments
- Ensure no duplicates
- Document port allocation scheme

---

#### Task 2.3: Add Missing Model Files

**Issue:** `/workspace/models/` only contains `.gitkeep`

**Options:**

1. **Download Pre-trained Models:**
```bash
cd /workspace/models
wget https://storage.googleapis.com/sahool-models/plant_disease.tflite
```

2. **Train New Models:**
```bash
cd /workspace
python scripts/train_models.py --output models/
```

3. **Graceful Degradation:**
```python
# In crop-intelligence-service
if not os.path.exists(MODEL_PATH):
    logger.warning("Model file not found, using fallback")
    return {"status": "model_unavailable"}
```

---

### Testing After Phase 2

```bash
# 1. Full deployment
docker compose up -d

# 2. Check all services
docker compose ps

# 3. Count healthy services
docker compose ps | grep -c "healthy"  # Should be 39

# 4. Test deprecated services (if kept)
curl http://localhost:8080/healthz  # field_ops
curl http://localhost:3000/healthz  # field-management-service

# 5. Verify both work and show deprecation
```

---

## Phase 3: Configuration Improvements

### Priority: 🟢 MEDIUM | Timeline: 2-4 hours

#### Task 3.1: Create Comprehensive .env.example

```bash
cat > .env.example << 'EOF'
# ═══════════════════════════════════════════════════════════════
# SAHOOL v16.0.0 Environment Variables
# ═══════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────
# Infrastructure - REQUIRED
# ─────────────────────────────────────────────────────────────
POSTGRES_USER=sahool
POSTGRES_PASSWORD=CHANGE_ME_PRODUCTION
POSTGRES_DB=sahool
POSTGRES_PORT=5432

REDIS_PASSWORD=CHANGE_ME_PRODUCTION
REDIS_PORT=6379

NATS_PORT=4222
NATS_MONITOR_PORT=8222

MQTT_PORT=1883
MQTT_WS_PORT=9001
MQTT_USER=sahool_iot
MQTT_PASSWORD=CHANGE_ME_PRODUCTION

# ─────────────────────────────────────────────────────────────
# Security - REQUIRED
# ─────────────────────────────────────────────────────────────
JWT_SECRET_KEY=CHANGE_ME_PRODUCTION_MIN_32_CHARS
JWT_ALGORITHM=RS256

# ─────────────────────────────────────────────────────────────
# API Gateway
# ─────────────────────────────────────────────────────────────
API_GATEWAY_PORT=8000
KONG_ADMIN_PORT=8001

# ─────────────────────────────────────────────────────────────
# Application Settings
# ─────────────────────────────────────────────────────────────
NODE_ENV=production
LOG_LEVEL=INFO
ENVIRONMENT=production

# CORS Settings
CORS_ALLOWED_ORIGINS=https://sahool.com,https://app.sahool.com

# ─────────────────────────────────────────────────────────────
# External APIs - OPTIONAL (features disabled without)
# ─────────────────────────────────────────────────────────────

# Satellite Imagery
SENTINEL_HUB_CLIENT_ID=
SENTINEL_HUB_CLIENT_SECRET=
NASA_EARTHDATA_USERNAME=
NASA_EARTHDATA_PASSWORD=
PLANET_API_KEY=
PLANET_CLIENT_ID=
USE_MULTI_PROVIDER=true

# Weather Services
OPENWEATHER_API_KEY=
OPENWEATHERMAP_API_KEY=
WEATHERAPI_KEY=
USE_MOCK_WEATHER=false

# AI Services
ANTHROPIC_API_KEY=
CLAUDE_MODEL=claude-3-5-sonnet-20241022
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o
GOOGLE_API_KEY=
GEMINI_MODEL=gemini-1.5-pro
PRIMARY_LLM_PROVIDER=anthropic

# Payment Processing
STRIPE_API_KEY=
STRIPE_WEBHOOK_SECRET=
THARWATT_BASE_URL=https://developers-test.tharwatt.com:5253
THARWATT_API_KEY=
THARWATT_MERCHANT_ID=
THARWATT_WEBHOOK_SECRET=

# Notifications
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=noreply@sahool.com
FCM_SERVER_KEY=

# ─────────────────────────────────────────────────────────────
# Observability - OPTIONAL
# ─────────────────────────────────────────────────────────────
GRAFANA_ADMIN_PASSWORD=admin

# ─────────────────────────────────────────────────────────────
# Vector Database
# ─────────────────────────────────────────────────────────────
QDRANT_HOST=qdrant
QDRANT_PORT=6333
EMBEDDING_MODEL=paraphrase-multilingual-MiniLM-L12-v2
EOF
```

---

#### Task 3.2: Update Kong Configuration

**File:** `/workspace/infrastructure/gateway/kong-legacy/kong.yml`

**Updates Needed:**
1. Add routes for new consolidated services
2. Remove routes for deprecated services
3. Update upstream URLs

**Example:**
```yaml
services:
  - name: field-management
    url: http://field-management-service:3000
    routes:
      - name: field-management-route
        paths:
          - /api/v1/fields
          - /api/v1/field-management
    plugins:
      - name: rate-limiting
        config:
          minute: 100
```

---

#### Task 3.3: Regenerate compose.generated.yml

**Issue:** Auto-generated file uses old service names

**Solution:**
```bash
# 1. Update governance/services.yaml with new names
# 2. Regenerate
make generate-infra

# Or manually:
cd /workspace
python scripts/generate-compose.py governance/services.yaml > docker/compose.generated.yml
```

---

### Testing After Phase 3

```bash
# 1. Validate all environment variables
docker compose config | grep -i "warning\|error"

# 2. Test with .env.example
cp .env.example .env.test
docker compose --env-file .env.test config > /dev/null

# 3. Test Kong routing
curl http://localhost:8000/api/v1/fields/health

# 4. Full system test
docker compose down
docker compose up -d
./scripts/health-check-all.sh
```

---

## Phase 4: Documentation and CI/CD

### Priority: 🔵 LOW | Timeline: 4-8 hours

#### Task 4.1: Update Documentation

**Files to Update:**
1. `/workspace/README.md` - Add new service architecture
2. `/workspace/docs/DEPLOYMENT.md` - Update deployment steps
3. `/workspace/docs/SERVICES.md` - Document all 39 services
4. `/workspace/docs/MIGRATION.md` - Create migration guide

---

#### Task 4.2: Update CI/CD Pipelines

**Files to Check:**
- `.github/workflows/*.yml`
- `infrastructure/ci/*.yml`

**Updates:**
- Use new service names in tests
- Update health check endpoints
- Fix integration test references

---

#### Task 4.3: Create Monitoring Dashboards

**Add to Grafana:**
1. Service Health Dashboard
2. Resource Usage Dashboard
3. Dependency Graph Visualization
4. Deprecated Service Usage Tracking

---

## Rollback Plan

### If Fixes Break Deployment

#### Step 1: Quick Rollback
```bash
# Restore backups
cd /workspace
mv docker-compose.yml.backup.* docker-compose.yml
mv docker/compose.dev.yml.backup.* docker/compose.dev.yml
mv docker/compose.prod.yml.backup.* docker/compose.prod.yml
mv docker/compose.staging.yml.backup.* docker/compose.staging.yml

# Remove symlink
rm -f infra

# Restart
docker compose down
docker compose up -d
```

---

#### Step 2: Partial Rollback

Keep fixes but revert specific changes:
```bash
# Restore only main file
mv docker-compose.yml.backup.* docker-compose.yml

# Keep override fixes
# Keep symlink
```

---

#### Step 3: Git Rollback

If committed:
```bash
git log --oneline | head -5
git revert <commit-hash>
git push
```

---

## Success Metrics

### Deployment Success
- [ ] All 6 infrastructure services healthy
- [ ] All 10 Node.js services healthy
- [ ] All 29 Python services healthy
- [ ] No service dependency errors in logs
- [ ] All health check endpoints return 200
- [ ] No port binding errors

### Performance Metrics
- [ ] All services start within 2 minutes
- [ ] Health check response time < 100ms
- [ ] Zero restart loops
- [ ] Memory usage within limits
- [ ] CPU usage < 50% idle

### Quality Metrics
- [ ] Zero critical errors in logs (first hour)
- [ ] All deprecated endpoints return warnings
- [ ] Kong routing works for all services
- [ ] Database migrations complete successfully
- [ ] Redis cache works
- [ ] NATS message queue operational

---

## Timeline Summary

| Phase | Priority | Time | Can Skip? |
|-------|----------|------|-----------|
| Phase 1: Critical Fixes | 🔴 CRITICAL | 1-2h | ❌ NO |
| Phase 2: Service Cleanup | 🟡 HIGH | 4-6h | ⚠️ For prod |
| Phase 3: Configuration | 🟢 MEDIUM | 2-4h | ✅ Yes |
| Phase 4: Documentation | 🔵 LOW | 4-8h | ✅ Yes |
| **TOTAL** | | **11-20h** | **Minimum: 1-2h** |

---

## Execution Checklist

### Pre-Deployment
- [ ] Read full analysis: `DOCKER_COMPOSE_ANALYSIS.md`
- [ ] Read this plan
- [ ] Backup current configuration
- [ ] Commit current state to git
- [ ] Stop all running containers
- [ ] Clear Docker volumes (if needed)

### Phase 1 Execution
- [ ] Run fix script: `./fix-docker-compose.sh`
- [ ] Review changes: `git diff`
- [ ] Validate config: `docker compose config`
- [ ] Test infrastructure: `docker compose up -d postgres redis nats`
- [ ] Test core services: `docker compose up -d field-management-service`
- [ ] Check logs: `docker compose logs --tail=100`

### Phase 2 Execution (Optional)
- [ ] Decide: Remove or keep deprecated services
- [ ] Update docker-compose.yml
- [ ] Test deployment
- [ ] Add model files if needed

### Phase 3 Execution (Optional)
- [ ] Create .env.example
- [ ] Update Kong config
- [ ] Regenerate compose.generated.yml
- [ ] Test with new config

### Phase 4 Execution (Optional)
- [ ] Update documentation
- [ ] Update CI/CD
- [ ] Create dashboards
- [ ] Announce changes to team

### Post-Deployment
- [ ] Monitor for 24 hours
- [ ] Check error rates
- [ ] Verify all features work
- [ ] Update runbooks
- [ ] Archive old backups

---

## Quick Reference

### Critical Files
```
/workspace/docker-compose.yml              # Main compose file
/workspace/docker/compose.dev.yml          # Dev overrides
/workspace/docker/compose.prod.yml         # Prod overrides
/workspace/docker/compose.staging.yml      # Staging overrides
/workspace/infrastructure/                 # Config files
/workspace/fix-docker-compose.sh           # Fix script
/workspace/DOCKER_COMPOSE_ANALYSIS.md      # Full analysis
/workspace/DOCKER_COMPOSE_SUMMARY.md       # Quick summary
```

### Critical Commands
```bash
# Fix everything
./fix-docker-compose.sh

# Validate
docker compose config

# Deploy infrastructure
docker compose up -d postgres redis nats mqtt kong qdrant

# Deploy all
docker compose up -d

# Check health
docker compose ps

# View logs
docker compose logs -f --tail=100

# Stop all
docker compose down

# Clean restart
docker compose down -v && docker compose up -d
```

---

**Plan Created:** 2025-12-28  
**Platform Version:** SAHOOL v16.0.0  
**Status:** ✅ Ready for Execution
