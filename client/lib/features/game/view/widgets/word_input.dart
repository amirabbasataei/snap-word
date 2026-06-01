import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_theme.dart';

class WordInput extends StatefulWidget {
  final String? startLetter;
  final bool enabled;
  final String? hintWord;
  final void Function(String word) onSubmit;

  const WordInput({
    super.key,
    this.startLetter,
    required this.enabled,
    this.hintWord,
    required this.onSubmit,
  });

  @override
  State<WordInput> createState() => _WordInputState();
}

class _WordInputState extends State<WordInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(WordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintWord != null && widget.hintWord != oldWidget.hintWord) {
      _controller.text = widget.hintWord!;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim();
    if (word.isEmpty || !widget.enabled) return;
    widget.onSubmit(word);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.startLetter != null
        ? 'type a word starting with ${widget.startLetter!.toUpperCase()}…'
        : 'type any word to start…';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.none,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: placeholder,
                prefixText: widget.startLetter != null
                    ? '${widget.startLetter!.toUpperCase()} '
                    : null,
                prefixStyle: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: widget.enabled ? _submit : null,
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
