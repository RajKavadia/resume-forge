import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resumetailor/services/deep_link_service.dart';
import 'package:resumetailor/services/gemini_service.dart';
import 'package:resumetailor/services/job_import_service.dart';
import 'package:resumetailor/screens/preview_screen.dart';
import 'package:resumetailor/services/journal_service.dart';
import 'package:resumetailor/services/screen_capture_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resumetailor/screens/journal_screen.dart';
import 'package:resumetailor/screens/job_feed_screen.dart';
import 'package:resumetailor/services/job_feed_service.dart';

typedef TailorResumeFn = Future<String> Function(
  String jobDescription, {
  required String apiKey,
  List<String> sectionsToOptimize,
  String customInstructions,
});

typedef SaveJournalFn = Future<void> Function(String html, String jobDescription);

Future<void> defaultSaveJournal(String html, String jobDescription) {
  return JournalService.add(
    html: html,
    jobDescription: jobDescription,
  );
}

class HomeScreen extends StatefulWidget {
  final TailorResumeFn tailorResume;
  final SaveJournalFn saveJournal;

  const HomeScreen({
    super.key,
    this.tailorResume = GeminiService.tailorResume,
    this.saveJournal = defaultSaveJournal,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefsApiKey = 'gemini_api_key';
  static const _autoGenerateOnCapture = true;

  final _apiKeyController = TextEditingController();
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
  final JobFeedService _jobFeedService = JobFeedService();
  final _customInstructionsController = TextEditingController();
  List<String> _sectionsToOptimize = ['Summary', 'Skills', 'Experience', 'Projects', 'Open Source', 'Education'];

  @override
  void initState() {
    super.initState();
    _loadSavedApiKey();
    _initDeepLinks();
    try {
      _captureSub = ScreenCaptureService.events().listen((event) {
        final type = event['type'];
        if (type == 'captured_text') {
          final text = (event['text'] as String?) ?? '';
          if (text.trim().isEmpty) return;
          if (!mounted) return;
          setState(() {
            _capturedEntries.insert(
              0,
              _CapturedEntry(
                timestamp: DateTime.now(),
                text: text,
              ),
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
          developer.log(
            'capture status',
            name: 'ResumeForge.Home',
            error: {'message': message},
          );
          setState(() {
            _importStatus = message;
          });
        }
      });
    } catch (_) {
      // Ignore capture channel failures in tests and on unsupported platforms.
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
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsApiKey) ?? '';
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = saved;
    });
  }

  @override
  void dispose() {
    _captureSub?.cancel();
    _deepLinkSub?.cancel();
    _apiKeyController.dispose();
    _customInstructionsController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onTailorPressed({String? jobDescription}) async {
    final apiKey = _apiKeyController.text.trim();
    final jd = (jobDescription ?? (_capturedEntries.isEmpty ? '' : _capturedEntries.first.text)).trim();
    if (apiKey.isEmpty) {
      setState(() => _errorMessage = 'Please enter your Gemini API key.');
      return;
    }
    if (jd.isEmpty) {
      setState(() => _errorMessage = 'Please capture text first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _updateCaptureStatus('Tailoring resume');
      developer.log(
        'Tailor requested',
        name: 'ResumeForge.Home',
        error: {'jdLength': jd.length},
      );
      if (_saveApiKey) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsApiKey, apiKey);
      }

      final optimizedHtml = await widget.tailorResume(
        jd,
        apiKey: apiKey,
        sectionsToOptimize: _sectionsToOptimize,
        customInstructions: _customInstructionsController.text.trim(),
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
          pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
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
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
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
          _CapturedEntry(
            timestamp: DateTime.now(),
            text: extracted,
          ),
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
                    if (_importStatus != null) ...[
                      _buildStatus(),
                      const SizedBox(height: 10),
                    ],
                    _buildApiKeyField(),
                    const SizedBox(height: 12),
                    _buildSectionSelector(),
                    const SizedBox(height: 12),
                    _buildCustomInstructionsField(),
                    const SizedBox(height: 12),
                    _buildCaptureControls(),
                    const SizedBox(height: 12),
                    if (_errorMessage != null) ...[
                      _buildError(),
                      const SizedBox(height: 10),
                    ],
                    _buildCapturedTextPanel(),
                    const SizedBox(height: 12),
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
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                              border: Border.all(color: const Color(0xFF2A2A3A)),
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
          Icon(Icons.screen_search_desktop_rounded,
              color: Colors.white.withAlpha(153), size: 16),
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
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 22),
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
                    'Powered by Gemini',
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
                      builder: (_) => JobFeedScreen(
                        jobService: _jobFeedService,
                        onTailor: (job) {
                          Navigator.of(context).pop();
                          _onTailorPressed(jobDescription: job.description);
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
          'Capture text from the screen, confirm the selection, and Gemini will tailor the resume from that text.',
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
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF6B6B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style:
                  const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
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
            const Icon(Icons.vpn_key_rounded,
                color: Color(0xFF3ECFCF), size: 16),
            const SizedBox(width: 6),
            const Text(
              'Gemini API Key',
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
              hintText: 'Paste your Gemini API key…',
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
                borderRadius: BorderRadius.circular(16)),
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
                      'Gemini is tailoring…',
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
                    Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 20),
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
    final availableSections = ['Summary', 'Skills', 'Experience', 'Projects', 'Open Source', 'Education'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, color: Color(0xFF6C63FF), size: 16),
            const SizedBox(width: 6),
            const Text(
              'Sections to Optimize',
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
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: availableSections.map((section) {
            final isSelected = _sectionsToOptimize.contains(section);
            return FilterChip(
              label: Text(section),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _sectionsToOptimize.add(section);
                  } else {
                    _sectionsToOptimize.remove(section);
                  }
                });
              },
              selectedColor: const Color(0xFF6C63FF).withAlpha(64),
              checkmarkColor: const Color(0xFF6C63FF),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: const Color(0xFF1A1A24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF2A2A38),
                ),
              ),
            );
          }).toList(),
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
            const Icon(Icons.edit_note_rounded,
                color: Color(0xFF6C63FF), size: 16),
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
              hintText: 'e.g. "Focus more on leadership skills" or "Keep it concise"',
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
                Text(
                  entry.text,
                  style: const TextStyle(color: Colors.white),
                ),
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

  const _CapturedEntry({
    required this.timestamp,
    required this.text,
  });
}
