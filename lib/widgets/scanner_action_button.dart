import 'package:flutter/material.dart';

import '../config/scanner_ui_config.dart';
import '../screens/scan_customer_screen.dart';

class ScannerActionButton extends StatelessWidget {
  const ScannerActionButton({
    super.key,
    this.config = fideliScannerConfig,
    this.scannerBuilder,
  });

  final ScannerUiConfig config;

  /// Permite sustituir la pantalla de escaneo sin modificar el menú.
  final WidgetBuilder? scannerBuilder;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1050;
    final buttonSize = config.size * (isDesktop ? 1.28 : 1);
    return SizedBox(
      width: config.shape == ScannerButtonShape.pill
          ? buttonSize * 1.65
          : buttonSize,
      height: buttonSize,
      child: FloatingActionButton(
        heroTag: 'fideli-global-scanner',
        tooltip: config.tooltip,
        backgroundColor: config.color,
        foregroundColor: config.foregroundColor,
        shape: switch (config.shape) {
          ScannerButtonShape.circle => const CircleBorder(),
          ScannerButtonShape.roundedSquare => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          ScannerButtonShape.pill => const StadiumBorder(),
        },
        onPressed: () => _openScanner(context),
        child: Icon(config.icon, size: buttonSize * .42),
      ),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    final builder = scannerBuilder ?? (_) => const ScanCustomerScreen();
    if (config.openMode == ScannerOpenMode.bottomSheet) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .94,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        config.screenTitle,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(child: builder(sheetContext)),
            ],
          ),
        ),
      );
      return;
    }
    if (config.openMode == ScannerOpenMode.topOverlay) {
      final overlayBuilder =
          scannerBuilder ?? (_) => const ScanCustomerScreen(compact: true);
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Cerrar escáner',
        barrierColor: const Color(0x660F0B12),
        transitionDuration: const Duration(milliseconds: 460),
        pageBuilder: (dialogContext, _, _) {
          final screen = MediaQuery.sizeOf(dialogContext);
          final panelHeight = (screen.height * .78)
              .clamp(300.0, 700.0)
              .toDouble();
          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.white,
                elevation: 24,
                shadowColor: const Color(0x33000000),
                borderRadius: BorderRadius.circular(30),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: (screen.width - 36).clamp(320.0, 1180.0).toDouble(),
                  height: panelHeight,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 14, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCE8EB),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Color(0xFFED5264),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    config.screenTitle,
                                    style: Theme.of(dialogContext)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const Text(
                                    'Escanea un QR o busca al cliente',
                                    style: TextStyle(
                                      color: Color(0xFF817A78),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(child: overlayBuilder(dialogContext)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leading: IconButton(
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            title: Text(
              config.screenTitle,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: builder(context),
        ),
      ),
    );
  }
}
