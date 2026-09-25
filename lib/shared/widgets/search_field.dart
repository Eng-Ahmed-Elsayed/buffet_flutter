import 'package:flutter/material.dart';

/// The design's search bar: a white pill-cornered field with a search icon at
/// its start and, once something is typed, a clear button at its end.
///
/// Styled by the theme's input decoration (white fill, primary border); this
/// only adds the icons and the clear behaviour.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: clearTooltip,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      );
}
