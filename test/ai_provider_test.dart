import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/ai_provider.dart';
import 'package:resumetailor/services/nvidia_service.dart';

void main() {
  group('AiProvider descriptors', () {
    test('NVIDIA is the resolved default provider', () {
      expect(AiProviders.defaultProvider, same(AiProviders.nvidia));
      expect(AiProviders.defaultProvider.id, equals('nvidia'));
      expect(AiProviders.resolve(null), same(AiProviders.nvidia));
      expect(AiProviders.resolve('unknown-provider'), same(AiProviders.nvidia));
    });

    test('NVIDIA endpoint is correct', () {
      expect(
        AiProviders.nvidia.endpoint,
        equals('https://integrate.api.nvidia.com/v1/chat/completions'),
      );
    });

    test('Groq endpoint is correct', () {
      expect(
        AiProviders.groq.endpoint,
        equals('https://api.groq.com/openai/v1/chat/completions'),
      );
    });

    test('auth header builder produces Bearer <key>', () {
      expect(AiProviders.nvidia.authHeader('abc123'), equals('Bearer abc123'));
      expect(AiProviders.groq.authHeader('xyz789'), equals('Bearer xyz789'));
    });

    test('lookup by id works and is case-insensitive', () {
      expect(AiProviders.byId('nvidia'), same(AiProviders.nvidia));
      expect(AiProviders.byId('groq'), same(AiProviders.groq));
      expect(AiProviders.byId('GROQ'), same(AiProviders.groq));
      expect(AiProviders.byId('  nvidia  '), same(AiProviders.nvidia));
      expect(AiProviders.byId('nope'), isNull);
      expect(AiProviders.byId(null), isNull);
    });
  });

  group('NvidiaService transport unchanged', () {
    test('service default descriptor resolves to NVIDIA endpoint/model', () {
      expect(
        NvidiaService.defaultProviderDescriptor,
        same(AiProviders.nvidia),
      );
      expect(
        NvidiaService.defaultProviderDescriptor.endpoint,
        equals('https://integrate.api.nvidia.com/v1/chat/completions'),
      );
      expect(
        NvidiaService.defaultProviderDescriptor.endpoint,
        equals(NvidiaService.endpoint),
      );
      expect(
        NvidiaService.defaultProviderDescriptor.defaultModel,
        equals(NvidiaService.defaultModel),
      );
    });
  });
}
