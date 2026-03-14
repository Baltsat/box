---
name: vitalis phase 0 implementation
description: VITALIS health app — Expo/RN frontend + FastAPI backend, personal health data collector with background HealthKit sync
type: project
---

VITALIS is a personal health data collection app at ~/research-lab/.

**Architecture:** Expo/React Native frontend (vitalis-app/) + FastAPI backend (vitalis-backend/) on VPS 35.192.111.203:8100.

**Why:** "invisible by design" — app collects health data silently, syncs to VPS, intelligence happens server-side, user interacts via Telegram. App UI is secondary — opened rarely to glance at dashboards.

**How to apply:** manual data entry is LOW priority. background sync is CRITICAL. dark theme. focus on data collection pipeline, not UI polish.

**Key decisions made (2026-03-14):**

- kept React Native (not Swift rewrite) — @kingstinct/react-native-healthkit supports enableBackgroundDelivery + subscribeToChanges
- backend refactored into modules (routes/, middleware/) with API key auth + rate limiting
- new /api/v1/sync endpoint for bulk health data ingestion with sync_checkpoint anchors
- background sync engine: observer queries per HK type, offline queue with exponential backoff
- dark theme (near-black #0A0A0F palette)
- onboarding refactored from 1878 lines into 7 step components
- expo-location + expo-battery for device context
- ornament-reverse reference docs at ~/research-lab/ornament-reverse/

**Known deferred items:**

- HTTPS/TLS — needs domain name (bare IP can't get Let's Encrypt)
- proper token auth (QR + Keychain) — current API key is in EXPO*PUBLIC*\* (extractable from bundle)
- lab review singleton draft pattern — should be labId-based
- thesaurus preloading dependency in lab flow

**Stats:** frontend ~13.5K LOC TypeScript, backend ~2.6K LOC Python, 16 backend tests passing.
