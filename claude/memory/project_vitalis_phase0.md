---
name: vitalis phase 0 implementation
description: VITALIS health app — Expo/RN frontend + FastAPI backend, personal health data collector with background HealthKit sync. comprehensive handoff at VITALIS-HANDOFF.md
type: project
---

VITALIS is a personal health data collection app at ~/research-lab/.

**Architecture:** Expo/React Native frontend (vitalis-app/) + FastAPI backend (vitalis-backend/) on VPS 35.192.111.203:8100.

**Why:** "invisible by design" — app collects health data silently, syncs to VPS, intelligence happens server-side, user interacts via Telegram. App UI is secondary — opened rarely to glance at dashboards.

**How to apply:** manual data entry is LOW priority. background sync is CRITICAL. dark theme. focus on data collection pipeline, not UI polish.

**Comprehensive handoff:** ~/research-lab/VITALIS-HANDOFF.md — full audit with gap analysis, file inventory, recommended next steps.

**Key decisions made (2026-03-14):**

- kept React Native (not Swift rewrite) — @kingstinct/react-native-healthkit supports enableBackgroundDelivery + subscribeToChanges
- backend refactored into modules (routes/, middleware/) with API key auth + rate limiting
- new /api/v1/sync endpoint for bulk health data ingestion with sync_checkpoint anchors
- background sync engine: observer queries per HK type, offline queue with exponential backoff
- dark theme (near-black #0A0A0F palette)
- onboarding refactored from 1878 lines into 7 step components
- expo-location + expo-battery for device context
- ornament-reverse reference docs at ~/research-lab/ornament-reverse/ (173 screenshots + full APK analysis)

**Current state (2026-03-14 audit):**

- frontend: 73 source files, 25 screens, 12 components, 5 services, 4 stores
- backend: 19 source files, 7 tables, 16 API endpoints, 16 tests passing
- fundamental misalignment: app is ornament clone (full UI), spec wants thin sensor client
- adversarial review: REJECT (security boundary, sync orchestration, state handling issues)
- critical gaps: no HTTPS, no real auth, sleep sync not projected, stub screens

**Known deferred items:**

- HTTPS/TLS — needs domain name (bare IP can't get Let's Encrypt)
- proper token auth (QR + Keychain) — current API key is in EXPO_PUBLIC_* (extractable from bundle)
- Telegram bot integration — core vision, not started
- tab structure consolidation — 5 tabs should be 4 per spec
- composite health score (0-100) — backend computes per-biomarker but not aggregate

**Stats:** frontend ~73 TS/TSX files, backend ~19 Python files, 16 backend tests passing.
