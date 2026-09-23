import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resumetailor/services/deep_link_service.dart';
import 'package:resumetailor/services/nvidia_service.dart';
import 'package:resumetailor/services/job_import_service.dart';
import 'package:resumetailor/screens/preview_screen.dart';
import 'package:resumetailor/services/journal_service.dart';
import 'package:resumetailor/services/screen_capture_service.dart';
import 'package:resumetailor/screens/journal_screen.dart';
import 'package:resumetailor/screens/jobs_list_screen.dart';
import 'package:resumetailor/models/job.dart';
import 'package:resumetailor/services/ai_model_config_service.dart';
import 'package:resumetailor/services/nvidia_models_service.dart';

typedef TailorResumeFn =
    Future<String> Function(
      String jobDescription, {
      required String apiKey,
      String? endpointOverride,
      String? modelOverride,
      List<String> sectionsToOptimize,
      String customInstructions,
      void Function(String stage)? onProgress,
    });

typedef SaveJournalFn =
    Future<void> Function(String html, String jobDescription);

Future<void> defaultSaveJournal(String html, String jobDescription) {
  return JournalService.add(html: html, jobDescription: jobDescription);
}

class HomeScreen extends StatefulWidget {
  final TailorResumeFn tailorResume;
  final SaveJournalFn saveJournal;

  const HomeScreen({
    super.key,
    this.tailorResume = NvidiaService.tailorResume,
    this.saveJournal = defaultSaveJournal,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _prefsApiKey = 'nvidia_api_key';
  static const _autoGenerateOnCapture = true;

  final _apiKeyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  String? _importStatus;
  // ignore: prefer_final_fields
  bool _saveApiKey = true;
  bool _isCapturing = false;
  bool _autoGenerateTriggered = false;
  StreamSubscription? _captureSub;
  StreamSubscription? _deepLinkSub;
  final List<_CapturedEntry> _capturedEntries = <_CapturedEntry>[];
  final _customInstructionsController = TextEditingController();
  final _jobDescriptionController = TextEditingController();
  List<String> _sectionsToOptimize = [
    'Skills',
    'Experience',
  ];

  bool _accessibilityEnabled = true;

  Future<void> _checkAccessibility() async {
    final v = await ScreenCaptureService.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() => _accessibilityEnabled = v);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccessibility();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedApiKey();
    _checkAccessibility();
    _initDeepLinks();
    if (!kIsWeb) {
      try {
        _captureSub = ScreenCaptureService.events().listen(
          (event) {
            final type = event['type'];
            if (type == 'captured_text') {
              final text = (event['text'] as String?) ?? '';
              if (text.trim().isEmpty) return;
              if (!mounted) return;
              setState(() {
                _capturedEntries.insert(
                  0,
                  _CapturedEntry(timestamp: DateTime.now(), text: text),
                );
              });
              if (_autoGenerateOnCapture &&
                  !_autoGenerateTriggered &&
                  !_isLoading &&
                  _apiKeyController.text.trim().isNotEmpty) {
                _autoGenerateTriggered = true;
                ScreenCaptureService.updateStatus(
                  'Generating tailored resume and preparing PDF',
                );
                _handleGeneratedResumeFromCapture(text);
              }
            } else if (type == 'status') {
              final message = (event['message'] as String?) ?? '';
              if (!mounted || message.trim().isEmpty) return;
              if (message.contains('alive') || message.contains('heartbeat')) {
                return;
              }
              developer.log(
                'capture status',
                name: 'ResumeForge.Home',
                error: {'message': message},
              );
              setState(() {
                _importStatus = message;
              });
            }
          },
          onError: (Object e) {
            developer.log(
              'capture events stream error',
              name: 'ResumeForge.Home',
              error: e,
            );
          },
        );
      } catch (_) {
        // Ignore capture channel failures in tests and on unsupported platforms.
      }
    }
  }

  Future<void> _initDeepLinks() async {
    try {
      developer.log('Initializing deep links', name: 'ResumeForge.Home');
      final initialLink = await DeepLinkService.getInitialLink();
      if (initialLink != null) {
        developer.log(
          'Initial link received',
          name: 'ResumeForge.Home',
          error: {'link': initialLink},
        );
        await _handleSharedUrl(initialLink);
      }

      _deepLinkSub = DeepLinkService.startListening((link) {
        _handleSharedUrl(link);
      });
    } catch (_) {
      // Ignore deep-link setup failures in tests and unsupported platforms.
    }
  }

  Future<void> _loadSavedApiKey() async {
    final config = await AiModelConfigService.load();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = config.apiKey;
      _endpointController.text = config.endpoint;
      _modelController.text = config.model;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureSub?.cancel();
    _deepLinkSub?.cancel();
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    _customInstructionsController.dispose();
    _jobDescriptionController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onTailorPressed({String? jobDescription}) async {
    final apiKey = _apiKeyController.text.trim();
    final pasted = _jobDescriptionController.text.trim();
    final captured =
        _capturedEntries.isEmpty ? '' : _capturedEntries.first.text.trim();
    final jd = (jobDescription ?? (pasted.isNotEmpty ? pasted : captured)).trim();
    if (apiKey.isEmpty) {
      setState(() => _errorMessage = 'Please enter your NVIDIA API key.');
      return;
    }
    if (jd.isEmpty) {
      setState(
        () => _errorMessage = kIsWeb
            ? 'Please paste a job description first.'
            : 'Please paste a job description or capture text first.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      developer.log(
        'Tailor requested',
        name: 'ResumeForge.Home',
        error: {'jdLength': jd.length},
      );
      final endpoint = _endpointController.text.trim();
      final model = _modelController.text.trim();
      if (_saveApiKey) {
        await AiModelConfigService.save(AiModelConfig(endpoint: endpoint.isEmpty ? AiModelConfig.defaultEndpoint : endpoint, model: model.isEmpty ? AiModelConfig.defaultModel : model, apiKey: apiKey));
      }

      final optimizedHtml = await widget.tailorResume(
        jd,
        apiKey: apiKey,
        endpointOverride: endpoint.isEmpty ? null : endpoint,
        modelOverride: model.isEmpty ? null : model,
        sectionsToOptimize: _sectionsToOptimize,
        customInstructions: _customInstructionsController.text.trim(),
        onProgress: (stage) {
          _updateCaptureStatus(stage);
        },
      );
      await _updateCaptureStatus('Resume tailored, opening preview');
      developer.log(
        'Tailoring complete',
        name: 'ResumeForge.Home',
        error: {'htmlLength': optimizedHtml.length},
      );

      await widget.saveJournal(optimizedHtml, jd);
      await _updateCaptureStatus('Resume saved to journal');
      developer.log('Journal saved', name: 'ResumeForge.Home');

      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FadeTransition(
                opacity: animation,
                child: PreviewScreen(
                  htmlContent: optimizedHtml,
                  autoDownload: true,
                ),
              ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSharedUrl(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      return;
    }

    developer.log(
      'Incoming shared URL',
      name: 'ResumeForge.Home',
      error: {'url': normalized},
    );

    if (!mounted) return;
    setState(() {
      _importStatus = 'Loading shared page...';
      _errorMessage = null;
    });

    try {
      final extracted = await JobImportService.importFromUrl(normalized);
      if (!mounted) return;

      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF15151D),
            title: const Text('Use shared text?'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    normalized,
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The page was loaded in headless mode and converted to text. Use this text to generate the resume?',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C27),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      extracted,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Proceed'),
              ),
            ],
          );
        },
      );

      if (shouldProceed != true) {
        setState(() {
          _importStatus = 'Shared text loaded. Waiting for confirmation...';
        });
        return;
      }

      setState(() {
        _capturedEntries.insert(
          0,
          _CapturedEntry(timestamp: DateTime.now(), text: extracted),
        );
        _importStatus = 'Shared text confirmed.';
      });
      await _onTailorPressed(jobDescription: extracted);
    } catch (e) {
      if (!mounted) return;
      developer.log(
        'Shared URL handling failed',
        name: 'ResumeForge.Home',
        error: e,
      );
      setState(() {
        _importStatus = 'Could not load shared URL.';
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleGeneratedResumeFromCapture(String text) async {
    if (!mounted) return;
    developer.log(
      'auto-generate from capture',
      name: 'ResumeForge.Home',
      error: {'capturedLength': text.length},
    );
    await _onTailorPressed();
  }

  Future<void> _updateCaptureStatus(String message) async {
    if (!mounted) return;
    setState(() => _importStatus = message);
    if (kIsWeb) return;
    try {
      await ScreenCaptureService.updateStatus(message);
    } catch (e) {
      developer.log(
        'capture status update skipped',
        name: 'ResumeForge.Home',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (!kIsWeb && !_accessibilityEnabled) ...[
                      _buildAccessibilityBanner(),
                      const SizedBox(height: 10),
                    ],
                    if (_importStatus != null) ...[
                      _buildStatus(),
                      const SizedBox(height: 10),
                    ],
                    _buildApiKeyField(),
                    const SizedBox(height: 12),
                    _buildModelConfigFields(),
                    const SizedBox(height: 12),
                    _buildSectionSelector(),
                    const SizedBox(height: 12),
                    _buildCustomInstructionsField(),
                    const SizedBox(height: 12),
                    _buildJobDescriptionField(),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 12),
                      _buildCaptureControls(),
                    ],
                    const SizedBox(height: 12),
                    if (_errorMessage != null) ...[
                      _buildError(),
                      const SizedBox(height: 10),
                    ],
                    if (!kIsWeb) ...[
                      _buildCapturedTextPanel(),
                      const SizedBox(height: 12),
                    ],
                    _buildTailorButton(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102A23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E5C3A)),
      ),
      child: Text(
        _importStatus!,
        style: const TextStyle(color: Color(0xFF7CFFB2), fontSize: 13),
      ),
    );
  }

  Widget _buildCapturedTextPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15151D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Captured Texts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Copy captured text',
                onPressed: _capturedEntries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: _capturedEntries
                                .map(
                                  (entry) =>
                                      '[${_formatCaptureTime(entry.timestamp)}] ${entry.text}',
                                )
                                .join('\n\n'),
                          ),
                        );
                        if (!mounted) return;
                        developer.log(
                          'captured text copied',
                          name: 'ResumeForge.Home',
                        );
                      },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_capturedEntries.isEmpty)
            const Text(
              'No captured text yet. Tap the screenshot button to capture the current page.',
              style: TextStyle(color: Colors.white70),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _capturedEntries.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = _capturedEntries[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        tooltip: 'Copy this capture',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: entry.text),
                          );
                          if (!mounted) return;
                          developer.log(
                            'capture copied',
                            name: 'ResumeForge.Home',
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showCaptureDialog(entry),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C27),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF2A2A3A),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatCaptureTime(entry.timestamp),
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(160),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry.text,
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to use this text',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(120),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF3D1F00), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFF8C00))),
      child: Row(children: [
        const Icon(Icons.accessibility_new, color: Color(0xFFFF8C00), size:18),
        const SizedBox(width:8),
        const Expanded(child: Text('Accessibility service disabled — tap to enable', style: TextStyle(color: Colors.white, fontSize:12))),
        TextButton(onPressed: () async { await ScreenCaptureService.openAccessibilitySettings(); await Future.delayed(const Duration(seconds:1)); _checkAccessibility(); }, child: const Text('Enable')),
      ]),
    );
  }

  Widget _buildCaptureControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15151D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.screen_search_desktop_rounded,
            color: Colors.white.withAlpha(153),
            size: 16,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Capture from screen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              setState(() => _isCapturing = !_isCapturing);
              try {
                if (_isCapturing) {
                  _autoGenerateTriggered = false;
                  await ScreenCaptureService.startOverlay();
                } else {
                  await ScreenCaptureService.stopOverlay();
                }
              } catch (e) {
                if (!mounted) return;
                setState(() => _isCapturing = false);
                developer.log(
                  'capture failed',
                  name: 'ResumeForge.Home',
                  error: e,
                );
                setState(() => _errorMessage = 'Capture failed: $e');
              }
            },
            icon: Icon(
              _isCapturing ? Icons.stop_circle_outlined : Icons.play_circle,
              size: 18,
            ),
            label: Text(_isCapturing ? 'Stop' : 'Start'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatCaptureTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ResumeForge AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'NVIDIA NIM',
                    style: TextStyle(
                      color: Colors.white.withAlpha(128),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Journal',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JournalScreen()),
                  );
                },
                icon: const Icon(Icons.book_rounded, color: Colors.white),
              ),
              IconButton(
                tooltip: 'Job Pulse',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => JobsListScreen(
                        onTailor: (Job job) async {
                          await _onTailorPressed(
                            jobDescription: job.description,
                          );
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.radar_outlined, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Tailor your resume\nto any job in seconds.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Capture text from the screen, confirm the selection, and NVIDIA NIM will tailor the resume from that text.',
            style: TextStyle(
              color: Colors.white.withAlpha(153),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3D1515),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7A2020)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF6B6B),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.vpn_key_rounded,
              color: Color(0xFF3ECFCF),
              size: 16,
            ),
            const SizedBox(width: 6),
            const Text(
              'NVIDIA API Key(s)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A38)),
          ),
          child: TextField(
            controller: _apiKeyController,
            focusNode: _apiKeyFocusNode,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.65,
            ),
            decoration: InputDecoration(
              hintText:
                  'Paste key(s) — comma or newline separated for rotation…',
              hintStyle: TextStyle(
                color: Colors.white.withAlpha(77),
                fontSize: 13.5,
                height: 1.65,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            ),
          ),
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _saveApiKey,
                onChanged: (v) => setState(() => _saveApiKey = v ?? true),
                side: const BorderSide(color: Color(0xFF2A2A38)),
                activeColor: const Color(0xFF3ECFCF),
                checkColor: Colors.black,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Remember on this device',
                style: TextStyle(
                  color: Colors.white.withAlpha(153),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTailorButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _isLoading
              ? const LinearGradient(
                  colors: [Color(0xFF444460), Color(0xFF336666)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isLoading
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withAlpha(100),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _onTailorPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'NVIDIA NIM is tailoring…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Tailor My Resume',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSectionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, color: Color(0xFF6C63FF), size: 16),
            const SizedBox(width: 6),
            const Text(
              'Tailor scope (fixed)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '1. AI formats the job description only.\n'
          '2. Then updates Skills and the first role only:\n'
          '   Senior Mobile Application Developer — OnlinePSBLoans, Ahmedabad.',
          style: TextStyle(
            color: Colors.white.withAlpha(200),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  List<String> _availableModels = List.from(NvidiaModelsService.curated);
  bool _modelsLoading = false;

  Future<void> _refreshModels() async {
    setState(() => _modelsLoading = true);
    final models = await NvidiaModelsService.fetch();
    if (!mounted) return;
    setState(() { _availableModels = models; _modelsLoading = false; });
  }

  void _applyPreset(String endpoint, String model, {String? apiKeyIfEmpty}) {
    setState(() {
      _endpointController.text = endpoint;
      _modelController.text = model;
      if (apiKeyIfEmpty != null && _apiKeyController.text.trim().isEmpty) {
        _apiKeyController.text = apiKeyIfEmpty;
      }
      if (!_availableModels.contains(model)) {
        _availableModels = [model, ..._availableModels];
      }
    });
  }

  Widget _buildModelConfigFields() {
    final current = _modelController.text.trim().isEmpty ? AiModelConfig.defaultModel : _modelController.text.trim();
    // Build a local copy: mutating _availableModels during build forces extra
    // work on every keyboard open (viewInsets rebuild). Never setState here.
    final models = <String>[..._availableModels];
    if (!models.contains(current)) models.insert(0, current);
    if (!models.contains(AiModelConfig.ollamaDefaultModel)) {
      models.add(AiModelConfig.ollamaDefaultModel);
    }
    if (!models.contains(AiModelConfig.groqDefaultModel)) {
      models.add(AiModelConfig.groqDefaultModel);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF15151D), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF2A2A3A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.api_rounded, color: Color(0xFF3ECFCF), size: 16), const SizedBox(width: 6), const Expanded(child: Text('Model Configuration', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))), if (_modelsLoading) const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)) else IconButton(icon: const Icon(Icons.refresh, size:16, color: Colors.white70), tooltip: 'Refresh NVIDIA models', onPressed: _refreshModels)]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(label: const Text('Groq Fast', style: TextStyle(fontSize: 11)), onPressed: () => _applyPreset(AiModelConfig.groqEndpoint, AiModelConfig.groqDefaultModel)),
          ActionChip(label: const Text('NVIDIA Fast', style: TextStyle(fontSize: 11)), onPressed: () => _applyPreset(AiModelConfig.defaultEndpoint, AiModelConfig.defaultModel)),
          ActionChip(label: const Text('Ollama Desktop', style: TextStyle(fontSize: 11)), onPressed: () => _applyPreset(AiModelConfig.ollamaDesktopEndpoint, AiModelConfig.ollamaDefaultModel, apiKeyIfEmpty: AiModelConfig.ollamaApiKeyPlaceholder)),
          ActionChip(label: const Text('Ollama Android', style: TextStyle(fontSize: 11)), onPressed: () => _applyPreset(AiModelConfig.ollamaAndroidEndpoint, AiModelConfig.ollamaDefaultModel, apiKeyIfEmpty: AiModelConfig.ollamaApiKeyPlaceholder)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _endpointController, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(labelText: 'API Endpoint', hintText: AiModelConfig.defaultEndpoint, labelStyle: TextStyle(color: Colors.white.withAlpha(120)), hintStyle: TextStyle(color: Colors.white.withAlpha(60), fontSize: 11), filled: true, fillColor: const Color(0xFF1A1A24), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A38))), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: current, isExpanded: true, dropdownColor: const Color(0xFF1A1A24), decoration: InputDecoration(labelText: 'Model', labelStyle: TextStyle(color: Colors.white.withAlpha(120)), filled: true, fillColor: const Color(0xFF1A1A24), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A38))), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(color: Colors.white, fontSize: 12), items: models.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(), onChanged: (v){ if(v!=null) setState(()=>_modelController.text=v); }),
        const SizedBox(height: 6),
        Text('Race mode: primary + fastest fallback run in parallel, first success wins. Local Ollama = single attempt, ~1-2s.', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11)),
      ]),
    );
  }

  Widget _buildJobDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.description_outlined,
              color: Color(0xFF6C63FF),
              size: 16,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Job Description',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (_jobDescriptionController.text.trim().isNotEmpty)
              TextButton(
                onPressed: () {
                  _jobDescriptionController.clear();
                  setState(() {});
                },
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.white.withAlpha(160),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A38)),
          ),
          child: TextField(
            controller: _jobDescriptionController,
            minLines: kIsWeb ? 8 : 5,
            maxLines: 16,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.55,
            ),
            decoration: InputDecoration(
              hintText: kIsWeb
                  ? 'Paste the LinkedIn / job posting text here…'
                  : 'Paste job description here (or use screen capture)…',
              hintStyle: TextStyle(
                color: Colors.white.withAlpha(77),
                fontSize: 13.5,
                height: 1.55,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomInstructionsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.edit_note_rounded,
              color: Color(0xFF6C63FF),
              size: 16,
            ),
            const SizedBox(width: 6),
            const Text(
              'Custom Build Instructions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A38)),
          ),
          child: TextField(
            controller: _customInstructionsController,
            maxLines: 3,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText:
                  'e.g. "Focus more on leadership skills" or "Keep it concise"',
              hintStyle: TextStyle(
                color: Colors.white.withAlpha(77),
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCaptureDialog(_CapturedEntry entry) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF15151D),
          title: const Text('Use this capture?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatCaptureTime(entry.timestamp),
                  style: TextStyle(
                    color: Colors.white.withAlpha(160),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(entry.text, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                const Text(
                  'Proceed with this captured text and generate the resume?',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    if (shouldProceed == true) {
      await _onTailorPressed(jobDescription: entry.text);
    }
  }
}

class _CapturedEntry {
  final DateTime timestamp;
  final String text;

  const _CapturedEntry({required this.timestamp, required this.text});
}
