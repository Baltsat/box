---
name: vitalis phase 0 implementation
description: health dashboard + biomarker system for Vitalis iOS app, extending lifeops backend
type: project
---

Vitalis health app — Phase 0 implementation in progress (2026-03-12).

**Why:** building Ornament Health clone (~60% of user value at ~4% of codebase). Phase 0 = biomarker dashboard + reference ranges + manual entry + profile.

**How to apply:**
- iOS app at ~/Vitalis (SwiftUI, iOS 17+, SwiftData for models)
- backend at VPS 35.192.111.203:8100 (FastAPI lifeops, routes_vitalis_biomarkers.py)
- ornament-reverse reference docs at ~/research-lab/ornament-reverse/
- API contract: /api/v1/biomarkers/thesaurus, /entries, /status, /profile
- 4 phases total: P0 dashboard, P1 lab OCR, P2 fasting+sleep, P3 health score+AI
- pbxproj update script at ~/Vitalis/update_pbxproj.py for adding new files
- existing sync pipeline (HealthKit → SyncEngine → health_metric) preserved untouched
