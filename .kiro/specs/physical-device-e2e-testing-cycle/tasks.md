# Implementation Plan: Practical Physical-Device Flutter E2E Harness

## Overview

Implement a host-side Dart CLI harness under a dedicated tooling directory such as `tool/physical_device_e2e/`. It runs the checked-out Flutter app on one configured physical Android device through ADB, discovers observable Flutter semantics/accessibility XML selectors, enters the runtime NVIDIA key and tailoring input through the UI, submits through the app's normal live path, validates tailored HTML and marker content, checks PDF only through remote existence and byte size, and writes compact per-step results. The harness must not modify application code or require application test hooks.

## Tasks

- [x] 1. Create the isolated Dart host-harness foundation
  - [x] 1.1 Create the host CLI entrypoint, library/test directories, typed interfaces, and process boundary for ADB commands without changing `lib/`, `android/`, `ios/`, or application test code.
    - Define interfaces for `DeviceAdapter`, accessibility inspection, UI driving, live-service observation, artifact validation, orchestration, and recording.
    - Restrict harness writes to configured test output and application-generated artifact locations.
    - _Requirements: 8.1, 8.2_
  - [x] 1.2 Define `Scenario`, selector/action specifications, device constraints, marker sets, artifact paths, timeout policy, secret reference, optional flags, `StepResult`, `RunRecord`, and artifact metadata models.
    - Include only non-secret input identifiers in records; represent secret input as redacted metadata.
    - Generate a unique run ID and output location for every execution.
    - _Requirements: 1.1, 2.3, 7.1, 7.2_
  - [ ]* 1.3 Add unit tests for model serialization, unique run IDs, per-step result states, UTC timestamps, and secret-field omission/redaction.
    - _Requirements: 2.3, 7.1, 7.2_

- [x] 2. Implement safe scenario and runtime-secret loading
  - [x] 2.1 Implement non-secret scenario-file parsing and validation for package name, designated device identity, launch command, selector hints, action sequence, tailoring input references, NVIDIA endpoint identity, marker sets, remote artifact paths, timeouts, and output root.
    - Reject inline API-key values and invalid output/artifact paths before device interaction.
    - _Requirements: 1.1, 2.2, 3.2, 4.1, 5.3, 8.2_
  - [x] 2.2 Implement just-in-time API-key reference resolution and secret-safe command/action/error serialization.
    - Pass the key only to the UI text-input operation; record `secret: true` and a safe length bucket at most.
    - Ensure XML captures, logs, diagnostics, exceptions, and run records cannot contain the raw key.
    - _Requirements: 2.2, 2.3, 7.1_
  - [ ]* 2.3 Add unit and property tests for nested redaction and inline-secret rejection.
    - **Property 2: Secret values never serialize**
    - **Validates: Requirement 2.3**

- [x] 3. Implement the ADB device adapter and physical-device preflight
  - [x] 3.1 Implement typed ADB operations for device listing/snapshot, app launch, accessibility XML dump, tap, text input, drag, scroll, and remote `stat`.
    - Return bounded, sanitized command results and never log secret arguments.
    - Do not implement download/pull operations for PDF inspection.
    - _Requirements: 1.1, 1.3, 3.3, 6.1, 6.2_
  - [x] 3.2 Implement preflight and launch gates for the configured authorized, online physical serial, optional model/Android/screen constraints, package, and launch result.
    - Record device ID, Android version, model, dimensions, package, run ID, launch result, and available build identity.
    - Stop before UI interaction when the device is unavailable, unauthorized, offline, mismatched, or the app cannot launch.
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 3.4_
  - [ ]* 3.3 Add adapter tests with fake ADB processes for device-state failures, launch failures, timeouts, shell escaping, and sanitized stderr.
    - _Requirements: 1.2, 1.3, 1.4_

- [ ] 4. Implement accessibility-informed selectors and UI actions
  - [ ] 4.1 Parse Flutter semantics/accessibility XML into a normalized node tree containing text, content description, role/class, enabled/clickable/editable state, and bounds.
    - Resolve unique semantic label/content description/exact text before normalized text, role/bounds, and documented coordinate fallback; fail safely on missing or ambiguous required controls.
    - _Requirements: 2.1, 3.1, 3.2_
  - [ ] 4.2 Implement the UI driver for the configured physical-device sequence: API-key text input, tailoring text input, taps, drag, scroll, submit, and generated-resume-state polling.
    - Capture a fresh hierarchy before selector use and verify post-action state where configured.
    - Record selector kind, safe node description, gesture summary, and outcome without sensitive text.
    - Stop the mandatory sequence on an incomplete required interaction and mark later required steps blocked.
    - _Requirements: 2.1, 2.2, 3.1, 3.3, 3.5_
  - [ ]* 4.3 Add unit and property tests for XML normalization, selector precedence, unique/missing/ambiguous nodes, bounds-derived coordinates, tap/drag/scroll mapping, and secret-safe text-input records.
    - **Property 1: Accessibility resolution is safe and ordered**
    - **Validates: Requirements 2.1, 3.1, 3.2**
  - [ ]* 4.4 Add a property test for failure projection: after a failed required interaction, later unattempted required steps are blocked and the run cannot be successful.
    - **Property 3: Failed required steps block later steps**
    - **Validates: Requirement 3.5**

- [ ] 5. Implement live NVIDIA provenance and generated artifact validators
  - [ ] 5.1 Implement a passive live-service observer/classifier that does not proxy, rewrite, mock, replay, or replace the app request.
    - Classify the interaction as `live` only when configured endpoint identity, current app-run correlation, and absence of mock/stub/fixture/replay/cache indicators all hold; record only safe endpoint/timing/outcome metadata.
    - Record endpoint mismatch, timeout, authentication failure, unusable response, or missing provenance as a mandatory service failure.
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - [ ] 5.2 Implement HTML discovery/inspection after the app reaches generated output.
    - Require existence, byte size greater than zero, readable/parseable content, and at least one configured heading, skills/competency marker, experience/employment marker, and tailored job keyword.
    - Keep marker results and artifact metadata independent from the live-service result.
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  - [ ] 5.3 Implement metadata-only PDF checking with remote `stat`.
    - Record `produced` only when the remote artifact exists and has bytes greater than zero; record `not_produced` without failing HTML verification.
    - Do not download, open, parse, inspect, or validate PDF contents.
    - _Requirements: 6.1, 6.2, 6.3_
  - [ ]* 5.4 Add unit and property tests for provenance classification, HTML marker completeness, and PDF no-download behavior.
    - **Property 4: Live classification requires all provenance conditions** — **Validates: Requirements 4.1, 4.2**
    - **Property 5: HTML tailoring requires every marker category** — **Validates: Requirements 5.2, 5.3, 5.5**
    - **Property 6: PDF metadata is independent and non-content-based** — **Validates: Requirements 5.2, 6.1, 6.2, 6.3**

- [ ] 6. Implement compact recording and cycle orchestration
  - [ ] 6.1 Implement the ordered orchestrator: create run context, preflight, launch, inspect selectors, inject key, enter tailoring input, perform gestures/submit, observe live service, validate HTML, stat PDF, and finalize the record.
    - Always write a compact `RunRecord` for success or stopped execution with device/application metadata, non-secret input identifiers, ordered per-step outcomes, live classification, HTML results, and PDF existence/size status.
    - Preserve later blocked steps after mandatory failure and keep each run in a distinct retained output directory.
    - _Requirements: 1.1–1.4, 2.1–2.3, 3.3–3.5, 4.1–4.4, 5.1–5.5, 6.1–6.3, 7.1, 7.2, 8.3_
  - [ ] 6.2 Add CLI commands for preflight, one full cycle, and explicit cleanup limited to generated test-output roots.
    - Ensure no command writes application source files or silently substitutes an emulator, mock, fixture, cached response, or service-only call.
    - _Requirements: 3.4, 4.5, 8.1, 8.2, 8.3_
  - [ ]* 6.3 Add unit/integration tests for success, preflight stop, launch stop, interaction stop, live-service failure, HTML failure, optional PDF absence, record persistence, and repeated-run isolation.
    - **Property 7: Repeated runs remain distinct** — **Validates: Requirements 7.1, 7.2**
    - _Requirements: 1.2, 1.4, 3.5, 4.4, 5.4, 5.5, 6.3, 7.1, 7.2_

- [ ] 7. Add optional supplemental capabilities without making them gates
  - [ ]* 7.1 Implement opt-in screen recording and supplemental diagnostics/evidence (screenshots, XML snapshots, filtered logcat, safe network metadata, or action traces), associated with steps and redacted before storage.
    - A collector failure is recorded separately and cannot fail the mandatory cycle; recording is never required for success.
    - _Requirements: 7.3, 7.4_
  - [ ]* 7.2 Implement opt-in supplemental validation tests and separate result fields, without coupling them to the mandatory physical-device result.
    - _Requirements: 7.5_
  - [ ]* 7.3 Implement opt-in source tracking and human-readable verdict formatting as supplemental outputs only.
    - Keep the mandatory record valid without either capability; enforce output-root/source-safe path policy regardless of whether source tracking is enabled.
    - **Property 8: Optional capabilities do not gate the mandatory cycle**
    - **Property 9: Harness output paths are source-safe**
    - **Validates: Requirements 7.3–7.6, 8.1, 8.2**

- [ ] 8. Wire the runnable scenario and physical-device smoke path
  - [ ] 8.1 Add a non-secret scenario configuration for the designated physical device, API-key reference, tailoring inputs, selector hints/actions, NVIDIA endpoint environment, HTML markers, remote HTML/PDF paths, timeouts, and optional flags.
    - Configure tap, drag, scroll, and text-input steps to match the live app UI; do not alter application code.
    - _Requirements: 1.1, 2.1, 2.2, 3.1, 3.3, 4.1, 5.3, 6.1, 8.1_
  - [ ] 8.2 Wire concrete adapters and validators into the CLI and add host-side automated test commands for the mandatory pure logic and adapter boundaries.
    - _Requirements: 3.4, 4.2, 5.2, 5.3, 7.1, 8.2_
  - [ ] 8.3 Add the runnable physical-device smoke/E2E command and its result assertions for preflight, launch, semantics/XML discovery, key and tailoring input, gestures, live NVIDIA path, non-empty tailored HTML/markers, and PDF remote metadata.
    - The command must record unavailable-device/service/configuration failures as typed results and must never fall back to an emulator or mock.
    - _Requirements: 1.1–6.3, 7.1, 8.1–8.3_

- [ ] 9. Checkpoint - Ensure mandatory host tests pass, the harness is source-isolated, and the task plan's required physical-device path is fully wired.

- [ ] 10. Final checkpoint - Ensure the compact record, live-path classification, HTML marker validation, PDF metadata-only check, and optional-capability separation are complete.

## Notes

- Tasks marked with `*` are optional and may be skipped for a faster MVP. The mandatory cycle is the host-side physical-device path and compact per-step/run recording; screen recording, supplemental diagnostics, supplemental tests, verdict formatting, and source tracking are not required for success.
- Implementation language is Dart. All tasks concern host tooling only; no application-code changes, widgets, test hooks, service substitutions, mocks, fixtures, or request interception may be added.
- PDF checks are remote existence and byte-size checks only. No PDF download or content inspection is part of the harness.
- The design's correctness properties are mapped to optional property-test subtasks; unit, adapter, and integration tests remain focused on mandatory behavior.
- The plan follows the required incremental code-generation prompt approach: each task builds on prior interfaces and ends with concrete wiring, with no orphaned components.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1", "3.1"] },
    { "id": 1, "tasks": ["1.2", "2.2", "3.2"] },
    { "id": 2, "tasks": ["1.3", "2.3", "3.3", "4.1", "5.1", "5.2", "5.3"] },
    { "id": 3, "tasks": ["4.2"] },
    { "id": 4, "tasks": ["4.3", "4.4", "5.4", "6.1"] },
    { "id": 5, "tasks": ["6.2", "6.3"] },
    { "id": 6, "tasks": ["7.1", "7.2", "7.3"] },
    { "id": 7, "tasks": ["8.1"] },
    { "id": 8, "tasks": ["8.2"] },
    { "id": 9, "tasks": ["8.3"] }
  ]
}
```
