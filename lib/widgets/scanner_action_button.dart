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
