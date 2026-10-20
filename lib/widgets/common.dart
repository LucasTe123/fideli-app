import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/fideli_theme.dart';

OverlayEntry? _activeNotice;

Future<T?> showAppleBottomSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  double initialChildSize = .58,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x42000000),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      reverseDuration: Duration(milliseconds: 330),
    ),
    builder: (sheetContext) => AnimatedPadding(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialChildSize,
        minChildSize: .42,
        maxChildSize: .94,
        snap: true,
        snapSizes: [initialChildSize, .94],
        builder: (context, controller) => TweenAnimationBuilder<double>(
          tween: Tween(begin: .94, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutBack,
          child: Material(
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8D4D2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(child: builder(context, controller)),
              ],
            ),
          ),
          builder: (context, scale, child) => Transform.scale(
            alignment: Alignment.bottomCenter,
            scale: scale,
            child: child,
          ),
        ),
      ),
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.floatingActionButton,
    this.maxContentWidth = 900,
  });
  final List<Widget> children;
  final Widget? floatingActionButton;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final gutter = desktop ? 34.0 : 16.0;
        final contentWidth = (constraints.maxWidth - gutter * 2)
            .clamp(0.0, maxContentWidth)
            .toDouble();
        return Stack(
          children: [
            ListView(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: desktop ? 20 : 16,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: contentWidth,
                    padding: EdgeInsets.all(desktop ? 30 : 0),
                    decoration: desktop
                        ? BoxDecoration(
                            color: FideliTheme.surface,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: FideliTheme.line),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
            if (floatingActionButton != null)
              Positioned(right: 16, bottom: 16, child: floatingActionButton!),
          ],
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(color: FideliTheme.muted)),
          ],
        ),
      ),
    );
  }
}

Future<String?> textDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void showMessage(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final publicMessage = _publicNotice(message);
  final text = _shortNotice(publicMessage);
  final isError = _isErrorNotice(publicMessage);
  _activeNotice?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppleTopNotice(
      message: text,
      isError: isError,
      onDismissed: () {
        if (_activeNotice == entry) _activeNotice = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _activeNotice = entry;
  overlay.insert(entry);
}

String _publicNotice(String message) {
  final value = message.toLowerCase();
  if (value.contains('supabase') ||
      value.contains('postgrest') ||
      value.contains('postgres') ||
      value.contains('.supabase.co') ||
      value.contains('/functions/v1/')) {
    return 'No se pudo completar. Revisa tu conexión.';
  }
  return message;
}

bool _isErrorNotice(String message) {
  final value = message.toLowerCase();
  return value.contains('no se pudo') ||
      value.contains('error') ||
      value.contains('insuficiente') ||
      value.contains('no encontrado') ||
      value.contains('no pertenece') ||
      value.contains('no está activa') ||
      value.contains('sin conexión');
}

String _shortNotice(String message) {
  final value = message.toLowerCase();
  if (value.contains('campaña') && value.contains('enviad')) {
    return 'Campaña enviada';
  }
  if (value.contains('campaña') && value.contains('eliminad')) {
    return 'Campaña eliminada';
  }
  if (value.contains('campaña') &&
      (value.contains('guardad') || value.contains('reutilizar'))) {
    return 'Campaña guardada';
  }
  if (value.contains('recompensa') && value.contains('canjead')) {
    return 'Recompensa canjeada';
  }
  if (value.contains('programa') && value.contains('eliminad')) {
    return 'Programa eliminado';
  }
  if (value.contains('cliente') && value.contains('eliminad')) {
    return 'Cliente eliminado';
  }
  if (value.contains('diseño guardado') ||
      value.contains('negocio actualizado') ||
      value.contains('icono guardado') ||
      value.contains('logo guardado') ||
      value.contains('cambios aplicados')) {
    return 'Cambios aplicados';
  }
  if (_isErrorNotice(message) && message.length > 42) {
    return 'No se pudo completar';
  }
  return message.length > 42 ? '${message.substring(0, 39)}…' : message;
}

class _AppleTopNotice extends StatefulWidget {
  const _AppleTopNotice({
    required this.message,
    required this.isError,
    required this.onDismissed,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismissed;

  @override
  State<_AppleTopNotice> createState() => _AppleTopNoticeState();
}

class _AppleTopNoticeState extends State<_AppleTopNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _spring;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _spring = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1900), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 18,
      right: 18,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final entrance = Curves.easeOutCubic.transform(_controller.value);
            final scale = .78 + (.22 * _spring.value);
            return Opacity(
              opacity: entrance.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, -64 * (1 - entrance)),
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 170,
                maxWidth: 310,
                minHeight: 50,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF2FFFFFF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1A000000)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isError ? Icons.close_rounded : Icons.check_rounded,
                    size: 20,
                    color: widget.isError
                        ? const Color(0xFFB3261E)
                        : FideliTheme.ink,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      widget.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF171717),
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
