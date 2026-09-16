import 'dart:convert';
import 'dart:io';

/// Resolves a configured secret reference only when the cycle is ready to
/// inject it into the application UI.
abstract interface class SecretProvider {
  Future<String?> resolve(String reference);
}

/// Resolves environment-backed references in the form `env:VARIABLE_NAME`.
/// The returned value is intentionally not retained by this class.
class EnvironmentSecretProvider implements SecretProvider {
  EnvironmentSecretProvider({Map<String, String>? environment})
      : _environment = environment;

  final Map<String, String>? _environment;

  @override
  Future<String?> resolve(String reference) async {
    if (!reference.startsWith('env:')) return null;
    final name = reference.substring(4);
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) return null;
    final environment = _environment ?? Platform.environment;
    return environment[name];
  }
}

class SecretResolutionException implements Exception {
  SecretResolutionException(this.message);
  final String message;

  @override
  String toString() => 'Secret resolution failed: $message';
}

/// JIT resolver. Call [resolveForUi] immediately before the text action and
/// never serialize the returned value.
class RuntimeSecretResolver {
  RuntimeSecretResolver(this.provider);

  final SecretProvider provider;

  Future<ResolvedSecret> resolveForUi(String reference) async {
    if (reference.trim().isEmpty) {
      throw SecretResolutionException('secret reference is empty');
    }
    final value = await provider.resolve(reference.trim());
    if (value == null || value.isEmpty) {
      throw SecretResolutionException('secret reference could not be resolved');
    }
    return ResolvedSecret._(value);
  }
}

/// Opaque runtime value. Its value is exposed only for the UI text operation.
class ResolvedSecret {
  ResolvedSecret._(this.value);
  final String value;

  SecretMetadata get metadata => SecretMetadata(
        secret: true,
        lengthBucket: secretLengthBucket(value.length),
      );
}

class SecretMetadata {
  const SecretMetadata({required this.secret, required this.lengthBucket});
  final bool secret;
  final String lengthBucket;

  Map<String, Object> toJson() => {
        'secret': secret,
        'length_bucket': lengthBucket,
      };
}

String secretLengthBucket(int length) {
  if (length == 0) return 'empty';
  if (length <= 8) return '1-8';
  if (length <= 32) return '9-32';
  if (length <= 64) return '33-64';
  return '65+';
}

/// Replaces classified secret values everywhere in nested records.
Object? redactSecrets(Object? value, {Iterable<String> secrets = const []}) {
  final known = secrets.where((secret) => secret.isNotEmpty).toList();
  String redactString(String input) {
    var result = input;
    for (final secret in known) {
      result = result.replaceAll(secret, '<redacted>');
    }
    return result;
  }

  if (value is String) return redactString(value);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): redactSecrets(entry.value, secrets: known),
    };
  }
  if (value is Iterable) {
    return value.map((item) => redactSecrets(item, secrets: known)).toList();
  }
  return value;
}

String safeError(Object error, {Iterable<String> secrets = const []}) {
  final message = redactSecrets(error.toString(), secrets: secrets);
  return message is String ? message : jsonEncode(message);
}
