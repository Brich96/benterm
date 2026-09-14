import 'package:flutter/material.dart';

/// The keys a soft keyboard does not have, for use on mobile.
///
/// Wrapped in a [Focus] that refuses focus so tapping a key never pulls
/// focus off the terminal — which would dismiss the on-screen keyboard.
class KeyToolbar extends StatelessWidget {
  const KeyToolbar({
    super.key,
    required this.ctrlActive,
    required this.altActive,
    required this.onToggleCtrl,
    required this.onToggleAlt,
    required this.onSend,
  });

  /// Whether the next character will be sent as a control character.
  final bool ctrlActive;

  /// Whether the next character will be prefixed with escape.
  final bool altActive;

  final VoidCallback onToggleCtrl;
  final VoidCallback onToggleAlt;

  /// Sends a literal sequence straight to the session.
  final void Function(String data) onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Material(
        color: colors.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                _Key(label: 'esc', onTap: () => onSend('\x1b')),
                _Key(label: 'tab', onTap: () => onSend('\t')),
                _Key(
                  label: 'ctrl',
                  active: ctrlActive,
                  onTap: onToggleCtrl,
                ),
                _Key(label: 'alt', active: altActive, onTap: onToggleAlt),
                _Key(label: '-', onTap: () => onSend('-')),
                _Key(label: '/', onTap: () => onSend('/')),
                _Key(label: '|', onTap: () => onSend('|')),
                _Key(label: '~', onTap: () => onSend('~')),
                _Key(icon: Icons.arrow_back, onTap: () => onSend('\x1b[D')),
                _Key(icon: Icons.arrow_downward, onTap: () => onSend('\x1b[B')),
                _Key(icon: Icons.arrow_upward, onTap: () => onSend('\x1b[A')),
                _Key(icon: Icons.arrow_forward, onTap: () => onSend('\x1b[C')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.active = false, required this.onTap});

  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? colors.primary : colors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: active ? colors.onPrimary : colors.onSurface,
                )
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? colors.onPrimary : colors.onSurface,
                  ),
                ),
        ),
      ),
    );
  }
}
