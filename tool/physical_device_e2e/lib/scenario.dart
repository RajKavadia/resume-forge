import 'dart:convert';
import 'dart:io';

class ScenarioValidationException implements Exception {
  ScenarioValidationException(this.errors);
  final List<String> errors;

  @override
  String toString() =>
      'Invalid scenario:\n${errors.map((e) => ' - $e').join('\n')}';
}

class Scenario {
  Scenario({
    required this.id,
    required this.packageName,
    required this.device,
    required this.launchCommand,
    required this.selectors,
    required this.actions,
    required this.tailoringInputs,
    required this.nvidiaEndpoint,
    required this.htmlMarkers,
    required this.artifactPaths,
    required this.timeouts,
    required this.outputRoot,
    required this.apiKeyRef,
    this.optional = const OptionalScenarioFeatures(),
  });

  final String id;
  final String packageName;
  final DeviceConstraints device;
  final String launchCommand;
  final List<SelectorHint> selectors;
  final List<ActionSpec> actions;
  final TailoringInputs tailoringInputs;
  final NvidiaEndpoint nvidiaEndpoint;
  final MarkerSets htmlMarkers;
  final ArtifactPaths artifactPaths;
  final TimeoutPolicy timeouts;
  final String outputRoot;
  final String apiKeyRef;
  final OptionalScenarioFeatures optional;

  factory Scenario.fromJson(Map<String, dynamic> json) {
    final errors = <String>[];
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        errors.add('$key must be a non-empty string');
        return '';
      }
      return value.trim();
    }

    final id = requiredString('id');
    final packageName = requiredString('package_name');
    final launchCommand = requiredString('launch_command');
    final outputRoot = requiredString('output_root');
    final apiKeyRef = requiredString('api_key_ref');

    final device = DeviceConstraints.fromJson(json['device'], errors);
    final selectors = _listOfMaps(json['selectors'], 'selectors', errors)
        .map((value) => SelectorHint.fromJson(value, errors))
        .toList(growable: false);
    final actions = _listOfMaps(json['actions'], 'actions', errors)
        .map((value) => ActionSpec.fromJson(value, errors))
        .toList(growable: false);
    final tailoring = TailoringInputs.fromJson(
      json['tailoring_inputs'],
      errors,
    );
    final endpoint = NvidiaEndpoint.fromJson(json['nvidia_endpoint'], errors);
    final markers = MarkerSets.fromJson(json['html_markers'], errors);
    final artifacts = ArtifactPaths.fromJson(json['artifact_paths'], errors);
    final timeouts = TimeoutPolicy.fromJson(json['timeouts'], errors);
    final optional = OptionalScenarioFeatures.fromJson(
      json['optional'],
      errors,
    );

    if (_containsSecretKey(json)) {
      errors.add('scenario must not contain inline API-key or secret values');
    }
    if (apiKeyRef.isNotEmpty && _looksLikeSecret(apiKeyRef)) {
      errors.add(
        'api_key_ref must be a secret-provider reference, not an inline secret',
      );
    }
    if (outputRoot.isNotEmpty && !_isSafeLocalOutputRoot(outputRoot)) {
      errors.add(
        'output_root must be a relative or absolute non-source test-output path',
      );
    }
    if (outputRoot.isNotEmpty &&
        artifacts.html.isNotEmpty &&
        !_isRemoteArtifactPath(artifacts.html)) {
      errors.add(
        'artifact_paths.html must be a non-empty remote absolute path',
      );
    }
    if (outputRoot.isNotEmpty &&
        artifacts.pdf.isNotEmpty &&
        !_isRemoteArtifactPath(artifacts.pdf)) {
      errors.add('artifact_paths.pdf must be a non-empty remote absolute path');
    }
    if (errors.isNotEmpty) throw ScenarioValidationException(errors);

    return Scenario(
      id: id,
      packageName: packageName,
      device: device,
      launchCommand: launchCommand,
      selectors: selectors,
      actions: actions,
      tailoringInputs: tailoring,
      nvidiaEndpoint: endpoint,
      htmlMarkers: markers,
      artifactPaths: artifacts,
      timeouts: timeouts,
      outputRoot: outputRoot,
      apiKeyRef: apiKeyRef,
      optional: optional,
    );
  }

  static Future<Scenario> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw ScenarioValidationException([
        'scenario root must be a JSON object',
      ]);
    }
    return Scenario.fromJson(decoded);
  }
}

class DeviceConstraints {
  DeviceConstraints(
    this.serial,
    this.model,
    this.androidVersion, {
    this.screenWidth,
    this.screenHeight,
  });
  final String serial;
  final String? model;
  final String? androidVersion;
  final int? screenWidth;
  final int? screenHeight;

  factory DeviceConstraints.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('device must be an object');
      return DeviceConstraints('', null, null);
    }
    final serial = _required(value['serial'], 'device.serial', errors);
    int? dimension(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! int || raw <= 0) {
        errors.add('device.$key must be a positive integer');
        return null;
      }
      return raw;
    }

    return DeviceConstraints(
      serial,
      _optional(value['model']),
      _optional(value['android_version']),
      screenWidth: dimension('screen_width'),
      screenHeight: dimension('screen_height'),
    );
  }
}

class SelectorHint {
  SelectorHint(
    this.id,
    this.label,
    this.text,
    this.contentDescription,
    this.role,
    this.required,
  );
  final String id;
  final String? label;
  final String? text;
  final String? contentDescription;
  final String? role;
  final bool required;

  factory SelectorHint.fromJson(
    Map<String, dynamic> value,
    List<String> errors,
  ) =>
      SelectorHint(
        _required(value['id'], 'selector.id', errors),
        _optional(value['label']),
        _optional(value['text']),
        _optional(value['content_description']),
        _optional(value['role']),
        value['required'] is bool ? value['required'] as bool : true,
      );
}

class ActionSpec {
  ActionSpec(this.id, this.type, this.selector, this.value, this.required);
  final String id;
  final String type;
  final String? selector;
  final String? value;
  final bool required;

  factory ActionSpec.fromJson(Map<String, dynamic> value, List<String> errors) {
    final type = _required(value['type'], 'action.type', errors);
    const allowed = {'tap', 'text', 'drag', 'scroll', 'submit', 'wait'};
    if (type.isNotEmpty && !allowed.contains(type))
      errors.add('action.type "$type" is unsupported');
    return ActionSpec(
      _required(value['id'], 'action.id', errors),
      type,
      _optional(value['selector']),
      _optional(value['value']),
      value['required'] is bool ? value['required'] as bool : true,
    );
  }
}

class TailoringInputs {
  TailoringInputs(this.resumeRef, this.jobRef);
  final String resumeRef;
  final String jobRef;
  factory TailoringInputs.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('tailoring_inputs must be an object');
      return TailoringInputs('', '');
    }
    return TailoringInputs(
      _required(value['resume_ref'], 'tailoring_inputs.resume_ref', errors),
      _required(value['job_ref'], 'tailoring_inputs.job_ref', errors),
    );
  }
}

class NvidiaEndpoint {
  NvidiaEndpoint(this.host, this.environment);
  final String host;
  final String environment;
  factory NvidiaEndpoint.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('nvidia_endpoint must be an object');
      return NvidiaEndpoint('', '');
    }
    return NvidiaEndpoint(
      _required(value['host'], 'nvidia_endpoint.host', errors),
      _required(value['environment'], 'nvidia_endpoint.environment', errors),
    );
  }
}

class MarkerSets {
  MarkerSets(this.heading, this.skills, this.experience, this.keyword);
  final List<String> heading, skills, experience, keyword;
  factory MarkerSets.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('html_markers must be an object');
      return MarkerSets([], [], [], []);
    }
    List<String> list(String key) {
      final raw = value[key];
      if (raw is! List ||
          raw.isEmpty ||
          raw.any((v) => v is! String || v.trim().isEmpty)) {
        errors.add('html_markers.$key must be a non-empty string list');
        return <String>[];
      }
      return raw.map((v) => (v as String).trim()).toList(growable: false);
    }

    return MarkerSets(
      list('heading'),
      list('skills'),
      list('experience'),
      list('keyword'),
    );
  }
}

class ArtifactPaths {
  ArtifactPaths(this.html, this.pdf);
  final String html, pdf;
  factory ArtifactPaths.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('artifact_paths must be an object');
      return ArtifactPaths('', '');
    }
    return ArtifactPaths(
      _required(value['html'], 'artifact_paths.html', errors),
      _required(value['pdf'], 'artifact_paths.pdf', errors),
    );
  }
}

class TimeoutPolicy {
  TimeoutPolicy(this.adb, this.interaction, this.generation);
  final int adb, interaction, generation;
  factory TimeoutPolicy.fromJson(dynamic value, List<String> errors) {
    if (value is! Map) {
      errors.add('timeouts must be an object');
      return TimeoutPolicy(0, 0, 0);
    }
    int positive(String key) {
      final v = value[key];
      if (v is! int || v <= 0)
        errors.add('timeouts.$key must be a positive integer (milliseconds)');
      return v is int ? v : 0;
    }

    return TimeoutPolicy(
      positive('adb'),
      positive('interaction'),
      positive('generation'),
    );
  }
}

class OptionalScenarioFeatures {
  const OptionalScenarioFeatures({
    this.recording = false,
    this.diagnostics = false,
    this.validationTests = false,
    this.sourceTracking = false,
    this.verdict = false,
  });
  final bool recording, diagnostics, validationTests, sourceTracking, verdict;
  factory OptionalScenarioFeatures.fromJson(
    dynamic value,
    List<String> errors,
  ) {
    if (value == null) return const OptionalScenarioFeatures();
    if (value is! Map) {
      errors.add('optional must be an object');
      return const OptionalScenarioFeatures();
    }
    bool flag(String key) {
      if (value[key] != null && value[key] is! bool)
        errors.add('optional.$key must be boolean');
      return value[key] == true;
    }

    return OptionalScenarioFeatures(
      recording: flag('recording'),
      diagnostics: flag('diagnostics'),
      validationTests: flag('validation_tests'),
      sourceTracking: flag('source_tracking'),
      verdict: flag('verdict'),
    );
  }
}

List<Map<String, dynamic>> _listOfMaps(
  dynamic value,
  String key,
  List<String> errors,
) {
  if (value is! List || value.isEmpty || value.any((v) => v is! Map)) {
    errors.add('$key must be a non-empty list of objects');
    return const [];
  }
  return value
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList(growable: false);
}

String _required(dynamic value, String key, List<String> errors) {
  if (value is! String || value.trim().isEmpty) {
    errors.add('$key must be a non-empty string');
    return '';
  }
  return value.trim();
}

String? _optional(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

bool _containsSecretKey(dynamic value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final originalKey = entry.key.toString().toLowerCase();
      final key = originalKey.replaceAll(RegExp(r'[-_]'), '');
      if (originalKey != 'api_key_ref' &&
          (key.contains('apikey') ||
              key == 'secret' ||
              key.contains('password') ||
              key.contains('token'))) return true;
      if (_containsSecretKey(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_containsSecretKey);
  }
  return false;
}

bool _looksLikeSecret(String value) =>
    value.startsWith('nvapi-') ||
    value.length > 40 && !value.contains('/') && !value.contains('://');

bool _isRemoteArtifactPath(String value) =>
    value.startsWith('/') && !value.contains('/../') && !value.endsWith('/..');

bool _isSafeLocalOutputRoot(String value) {
  final normalized = value.replaceAll('\\', '/').toLowerCase();
  const forbidden = [
    '/lib/',
    '/android/',
    '/ios/',
    '/test/',
    '/integration_test/',
    '/web/',
    '/windows/',
    '/macos/',
    '/linux/',
  ];
  return !forbidden.any(normalized.contains) &&
      !normalized.endsWith('/lib') &&
      !normalized.endsWith('/android') &&
      !normalized.endsWith('/ios') &&
      !normalized.endsWith('/test');
}
