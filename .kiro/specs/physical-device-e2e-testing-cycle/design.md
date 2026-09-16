# Design Document: Practical Physical-Device Flutter E2E Cycle

## Overview

This design defines a host-side harness for one repeatable Flutter Android end-to-end cycle on a configured physical device. It launches the checked-out app, discovers the current UI from Flutter semantics/accessibility XML, injects a runtime NVIDIA API key into the visible field, performs the required taps, text entry, dragging, and scrolling, and submits tailoring input through the application's normal live NVIDIA path. It then verifies tailored HTML content and checks PDF output only through remote existence and byte-size metadata.

The harness is deliberately separate from application code. It adds no widgets, test hooks, service substitutions, mocks, fixtures, request interception, or production configuration. Screen recording, supplemental diagnostics/evidence, supplemental validation tests, verdict summaries, and source tracking are optional capabilities; none is a mandatory success gate.

## Goals and Non-goals

### Goals

- Exercise the checked-out application on the designated ADB-connected physical Android device.
- Discover selectors from observable Flutter semantics and Android accessibility XML before using coordinate fallback.
- Enter the runtime API key and tailoring data through the same UI path a user uses.
- Exercise the configured live NVIDIA endpoint through the running app, without a harness replacement request.
- Verify that the app reaches generated output and produces tailored HTML with required scenario markers.
- Check PDF output only for remote existence and byte size; never download it for content inspection.
- Produce a compact, non-secret run record for both successful and stopped cycles.
- Keep the mandatory cycle practical: optional diagnostics must not obscure the core app-working path.

### Non-goals

- Modifying application source or adding production test seams.
- Running the mandatory cycle against an emulator, mock, stub, fixture, cached response, or service-only call.
- Downloading or parsing PDF contents.
- Making screen recording, supplemental diagnostics, extra tests, source fingerprints, or a final verdict field prerequisites for success.
- Requiring a broad evidence package when a step result and required artifact metadata are sufficient.

## Architecture

```text
Host harness
  Scenario + secret reference
          |
   Cycle Orchestrator
    /       |        \
Preflight  UI Driver  Result Recorder
              |          |
      ADB/Accessibility  HTML validator + PDF stat checker
              |          |
      Designated physical Android device -- normal app path -- Live NVIDIA API
```

### Cycle Orchestrator

Owns the ordered lifecycle and stops on mandatory failures:

1. Create a unique run context and validate non-secret configuration.
2. Preflight the configured physical device and launch the app.
3. Capture accessibility XML and resolve the API-key and tailoring controls.
4. Inject the runtime key through the UI, enter tailoring input, and execute required gestures.
5. Submit through the app and wait for the generated-resume state.
6. Classify the NVIDIA interaction as live using safe provenance metadata.
7. Inspect generated HTML and remotely stat PDF metadata.
8. Write the run record and retain outputs in the designated test location.

Optional collectors are invoked only when enabled and run after/beside the mandatory step; failure of an optional collector is recorded separately and does not fail the core cycle.

### Scenario Configuration

The scenario file contains the package name, designated device identity constraints, app launch command, UI selector hints, safe scenario input identifiers or references, expected HTML marker sets, remote artifact paths, timeout values, output roots, and optional feature flags. The runtime API key is referenced through an approved secret provider and is never stored in the scenario file or run record.

### ADB and Device Adapter

The adapter is the only boundary for device operations. It supports device listing/snapshot, app launch, semantics/accessibility XML dump, screen dimensions, UI text input, tap, swipe/drag, scroll, remote file stat, and optional screenshot/screenrecord/logcat collection. It exposes typed results with sanitized errors and never logs secret arguments.

```text
DeviceAdapter {
  list_devices() -> [Device]
  snapshot(serial) -> DeviceSnapshot
  launch(serial, package) -> LaunchResult
  accessibility_xml(serial) -> XmlCapture
  tap(serial, point) -> ActionResult
  drag(serial, start, end, duration_ms) -> ActionResult
  scroll(serial, start, end, duration_ms) -> ActionResult
  text(serial, value, secret: bool) -> ActionResult
  stat(serial, remote_path) -> FileMetadata
  optional_collect(step, options) -> OptionalEvidenceResult
}
```

The adapter must not install altered application code or change request behavior. Installation, if explicitly configured, uses the checked-out application artifact only and is reported as setup, not as an application modification.

### Accessibility Inspector and UI Driver

The inspector parses Flutter semantics/accessibility XML into a normalized tree containing visible text, content description, role/class, enabled/clickable/editable state, and bounds. Selector resolution uses this precedence:

1. stable semantic label, resource/content description, or exact visible text;
2. normalized text plus role/class;
3. role/class and bounds/state;
4. documented coordinate fallback only when no observable node is available.

A required selector with zero or multiple unsafe matches fails the step rather than silently choosing. The driver records only selector metadata and a redacted action summary. It supports tap, text input, drag, and scroll, and checks the post-action hierarchy or expected visible state after each required interaction.

### Live NVIDIA Observer

The application itself constructs and sends the request. The observer does not proxy, rewrite, mock, replay, or substitute the request. It classifies the interaction using configured endpoint identity plus safe timing/correlation/application-log or approved network metadata. Bodies and credentials are not captured.

A request is `live` only when it is associated with this run and app session, reaches the configured NVIDIA endpoint, and has no mock, stub, fixture, replay, or cache indicator. Timeout, authentication failure, endpoint mismatch, unusable response, or missing live provenance fails the mandatory service step.

### Artifact Validators

HTML is inspected only after the app has reached its generated output. The validator checks existence, byte size greater than zero, readable/parseable content, and scenario markers: at least one heading, one skills/competency marker, one experience/employment marker, and one tailored job keyword.

PDF handling is intentionally narrower. The harness calls remote `stat` (or an equivalent metadata-only device operation), records existence and byte size, and does not pull, download, open, parse, or content-inspect the PDF. A missing PDF is recorded as `not_produced` and does not fail otherwise successful HTML verification.

### Run Recorder

The recorder writes one unique run record under the configured test output root. It includes run ID, scenario ID, device identity/version/model/dimensions, package and launch result, non-secret input identifiers, ordered step outcomes, live-service classification, HTML marker results, HTML artifact metadata, and PDF existence/size status. It excludes the raw API key and sensitive request content.

Optional evidence is associated with a step when enabled. Optional screen recordings, diagnostics, validation-test results, source tracking, and human-readable verdict summaries use separate optional fields/outputs and cannot become implicit mandatory gates.

## Execution and Failure Flow

Each mandatory step has a bounded timeout and a result of `passed`, `failed`, or `blocked`. Preflight failure stops before app interaction. Launch failure stops before tailoring input. Missing API-key control or failed key entry stops before submit. Any required gesture or selector failure stops subsequent mandatory interaction and records the failed step plus later blocked steps.

After submission, the harness waits for the normal generated-resume UI state. A live NVIDIA failure is recorded as a service failure. HTML validation is mandatory. PDF status is recorded independently. The recorder always attempts to write the run record after a stop, while optional diagnostics are best-effort.

Output directories are unique per run and are retained until an explicit cleanup command. Cleanup is outside the cycle and must not target application source directories.

## Data Models

```text
Scenario {
  id: string
  package_name: string
  device: { serial: string, model?: string, android_version?: string }
  nvidia_endpoint: { host: string, environment: string }
  api_key_ref: string
  selectors: [SelectorSpec]
  actions: [ActionSpec]
  html_markers: { heading: [string], skills: [string], experience: [string], keyword: [string] }
  artifact_paths: { html: string, pdf: string }
  output_root: path
  timeouts: { adb: duration, interaction: duration, generation: duration }
  optional: { recording: bool, diagnostics: bool, validation_tests: bool, source_tracking: bool, verdict: bool }
}

RunRecord {
  schema_version: string
  run_id: string
  scenario_id: string
  timestamps: { started: timestamp, finished: timestamp }
  device: DeviceSnapshot
  application: { package: string, launch: StepResult, build_id?: string }
  inputs: { resume_id?: string, job_id?: string, api_key: redacted }
  steps: [StepResult]
  live_service: { classification: live | not_live | failed | unknown, endpoint_class?: string, outcome?: string }
  html: { exists: bool, bytes: integer, readable: bool, markers: MarkerResults, passed: bool }
  pdf: { status: produced | not_produced | unknown, exists?: bool, bytes?: integer }
  optional: { evidence?: [EvidenceResult], validation_tests?: [ValidationResult], verdict?: string }
}
```

`ActionResult` stores action type, selector kind, safe node description, gesture summary, timestamp, and outcome. Secret text stores only `secret: true` and an optional length bucket. `ArtifactMetadata` stores remote path identifier, existence, byte size, and status; it does not imply that PDF content was transferred.

## Error Handling and Security

ADB errors include exit code and sanitized stderr. XML parse errors retain a bounded diagnostic only when optional diagnostics are enabled. Selector ambiguity, missing controls, failed gestures, live-service failures, and invalid HTML each produce actionable step errors and stop the mandatory flow as appropriate.

The key is resolved just in time, held in memory for UI entry, and passed only to the UI input operation. Redaction occurs before serialization. No XML dump, action trace, log, optional evidence, exception, or run record may contain the raw key. The harness rejects inline secret values in scenario configuration.

All writes are checked against the configured test output root and application-designated generated-output locations. The harness does not write to `lib/`, `android/`, `ios/`, `test/`, or other application source directories. Source tracking, when enabled, is supplemental diagnostics rather than a mandatory gate; the no-source-modification boundary is enforced by path policy and review of harness operations.

## Testing Strategy

Use focused unit/property tests for XML normalization and selector precedence, redaction, failed-step projection, live classification, HTML marker matching, artifact metadata modeling, PDF no-download behavior, run ID uniqueness, and output-root allowlisting. Use representative adapter/integration tests for ADB command mapping and record serialization. Use the designated physical device for the mandatory smoke/E2E cycle: preflight, launch, semantics-driven UI actions, live NVIDIA request, tailored HTML verification, and PDF remote stat. Optional recording, diagnostics, validation tests, source tracking, and verdict formatting are tested only when their flags are enabled.

The prework classified infrastructure and live-device criteria as integration/smoke/example tests and retained properties only where varied inputs exercise pure harness logic. Property reflection consolidated overlapping selector properties, artifact existence/validation properties, and failure/reporting properties so each remaining property has unique validation value. Property tests should use at least 100 iterations and include tags of the form `Feature: physical-device-e2e-testing-cycle, Property N`.

## Correctness Properties

*A property is a characteristic or behavior that should hold across all valid executions of a system—an executable bridge between requirements and automated verification.*

### Property 1: Accessibility resolution is safe and ordered

For any accessibility tree and selector set, a unique semantic/accessibility match is selected before coordinate fallback, and an absent or ambiguous required match produces a failure without inventing a target.

**Validates: Requirements 2.1, 3.1, 3.2**

### Property 2: Secret values never serialize

For any run record, action trace, optional evidence item, or diagnostic containing a classified secret, serialization contains only redacted metadata and never the raw secret value.

**Validates: Requirements 2.3**

### Property 3: Failed required steps block later steps

For any ordered mandatory action sequence containing a failed required step, the recorder marks that step failed and every later unattempted required step blocked, without reporting the sequence as successful.

**Validates: Requirements 3.5**

### Property 4: Live classification requires all provenance conditions

For any service observation, classification is `live` if and only if the endpoint matches the configured NVIDIA endpoint, the event is correlated to the current application run, and no mock, stub, fixture, replay, or cache indicator is present.

**Validates: Requirements 4.1, 4.2**

### Property 5: HTML tailoring requires every marker category

For any readable non-empty HTML document and configured marker sets, tailored-resume validation passes only when at least one heading, skills/competency marker, experience/employment marker, and tailored job keyword matches; removing any required category makes validation fail.

**Validates: Requirements 5.2, 5.3, 5.5**

### Property 6: PDF metadata is independent and non-content-based

For any PDF metadata result, the PDF check depends only on remote existence and byte size greater than zero, never requests content transfer or parsing, and a `not_produced` PDF does not change a passing HTML result.

**Validates: Requirements 5.2, 6.1, 6.2, 6.3**

### Property 7: Repeated runs remain distinct

For any sequence of repeated cycles using one scenario, each cycle receives a distinct run ID and output location, and writing a later record does not overwrite an earlier record.

**Validates: Requirements 7.1, 7.2**

### Property 8: Optional capabilities do not gate the mandatory cycle

For any valid mandatory cycle, disabling recording, supplemental evidence, supplemental validation tests, source tracking, or final verdict formatting leaves mandatory step and tailored-resume results evaluable; enabled optional failures are reported separately.

**Validates: Requirements 7.3, 7.4, 7.5, 7.6**

### Property 9: Harness output paths are source-safe

For any harness output path, the allowlist accepts only designated test/output locations and rejects application source locations; accepted operations cannot modify application source files.

**Validates: Requirements 8.1, 8.2**

## Traceability Summary

- Requirements 1.x: `CycleOrchestrator`, `DeviceAdapter`, launch/preflight step results.
- Requirements 2.x–3.x: `AccessibilityInspector`, `UiDriver`, secret-safe action records, and mandatory physical gestures.
- Requirements 4.x: `LiveNvidiaObserver` and normal application request path.
- Requirements 5.x: generated-state wait, `HtmlValidator`, marker model, and run record.
- Requirement 6.x: metadata-only `PdfStatChecker`; no download/content inspection.
- Requirements 7.x: compact records, unique run directories, and optional capability flags.
- Requirements 8.x: output-root allowlist and source-isolated harness boundary.
