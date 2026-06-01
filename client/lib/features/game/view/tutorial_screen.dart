import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  int _step = 0;
  final List<String> _chain = [];
  String? _errorMessage;

  final DictionaryService _dict = getIt<DictionaryService>();

  // Tutorial steps spec from CLAUDE.md
  static const _steps = [
    _TutorialStep(
      stepOf: 'STEP 1 OF 4',
      title: 'Start the chain!',
      instruction: 'Type any word to start the chain!',
      detail: null,
    ),
    _TutorialStep(
      stepOf: 'STEP 2 OF 4',
      title: 'Keep the chain going!',
      instruction: 'Type a word that starts with the last letter of the previous word.',
      detail: null,
    ),
    _TutorialStep(
      stepOf: 'STEP 3 OF 4',
      title: 'No repeats!',
      instruction: 'Great! Keep going — you can\'t reuse words.',
      detail: null,
    ),
    _TutorialStep(
      stepOf: 'STEP 4 OF 4',
      title: 'You\'re ready!',
      instruction: 'Try Classic, Time Attack, or the Daily Challenge.',
      detail: null,
    ),
  ];

  String get _requiredLetter =>
      _chain.isNotEmpty ? _chain.last[_chain.last.length - 1].toUpperCase() : '';

  void _submit(String word) {
    final normalized = word.trim().toLowerCase();
    setState(() => _errorMessage = null);

    if (_step == 3) {
      // Final step — just complete tutorial
      _completeTutorial();
      return;
    }

    if (normalized.length < 3) {
      setState(() => _errorMessage = 'Word must be at least 3 letters!');
      return;
    }

    if (!RegExp(r'^[a-z]+$').hasMatch(normalized)) {
      setState(() => _errorMessage = 'Only letters allowed!');
      return;
    }

    if (_chain.isNotEmpty && normalized[0] != _chain.last[_chain.last.length - 1]) {
      setState(() {
        _errorMessage =
            'Word must start with "${_chain.last[_chain.last.length - 1].toUpperCase()}"!';
      });
      return;
    }

    if (_chain.contains(normalized)) {
      setState(() => _errorMessage = 'That word was already used!');
      return;
    }

    if (!_dict.isValid(normalized)) {
      setState(() => _errorMessage =
          'Invalid words show a gentle hint — no penalty during the tutorial!');
      return;
    }

    setState(() {
      _chain.add(normalized);
      if (_step < 3) _step++;
    });
  }

  void _skip() => _completeTutorial();

  Future<void> _completeTutorial() async {
    final prefs = getIt<SharedPreferences>();
    await prefs.setBool('tutorial_completed', true);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step dots + Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Row(
                    children: List.generate(4, (i) {
                      return Container(
                        width: i == _step ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: i == _step
                              ? AppColors.primary
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _skip,
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // Step card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⭐ ', style: TextStyle(fontSize: 14)),
                        Text(
                          step.stepOf,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.instruction,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Required letter display
            if (_chain.isNotEmpty) ...[
              Center(
                child: Text(
                  'NEXT WORD MUST START WITH…',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.secondary, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _requiredLetter,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Chain so far
            if (_chain.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: const Text(
                  'YOUR CHAIN SO FAR:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _chain.length,
                  itemBuilder: (context, i) {
                    final isLast = i == _chain.length - 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'YOU  ',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isLast
                                    ? AppColors.primary
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _chain[i].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isLast)
                          const Padding(
                            padding: EdgeInsets.only(left: 36),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ] else
              const Spacer(),

            // Error / hint message
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Text('💡 ', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Input
            if (_step < 3)
              _TutorialInput(
                placeholder: _chain.isEmpty
                    ? 'type any word…'
                    : 'type a word starting with ${_requiredLetter.toLowerCase()}…',
                onSubmit: _submit,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ElevatedButton(
                  onPressed: _completeTutorial,
                  child: const Text('Start Playing'),
                ),
              ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _TutorialInput extends StatefulWidget {
  final String placeholder;
  final void Function(String) onSubmit;

  const _TutorialInput({required this.placeholder, required this.onSubmit});

  @override
  State<_TutorialInput> createState() => _TutorialInputState();
}

class _TutorialInputState extends State<_TutorialInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    widget.onSubmit(word);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(hintText: widget.placeholder),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(Icons.arrow_forward, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialStep {
  final String stepOf;
  final String title;
  final String instruction;
  final String? detail;

  const _TutorialStep({
    required this.stepOf,
    required this.title,
    required this.instruction,
    required this.detail,
  });
}
