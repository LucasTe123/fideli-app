import 'package:flutter/material.dart';

/// Configuración visual y de navegación del acceso global al escáner.
/// Cambiar estos valores modifica el botón QR en toda la aplicación.
enum ScannerButtonShape { circle, roundedSquare, pill }

enum ScannerOpenMode { fullScreen, bottomSheet }

class ScannerUiConfig {
  const ScannerUiConfig({
    this.color = const Color(0xFF1D1D21),
    this.foregroundColor = Colors.white,
    this.icon = Icons.qr_code_scanner_rounded,
    this.shape = ScannerButtonShape.circle,
    this.openMode = ScannerOpenMode.fullScreen,
    this.screenTitle = 'Escanear cliente',
    this.tooltip = 'Escanear QR de cliente',
    this.size = 64,
  });

  final Color color;
  final Color foregroundColor;
  final IconData icon;
  final ScannerButtonShape shape;
  final ScannerOpenMode openMode;
  final String screenTitle;
  final String tooltip;
  final double size;
}

/// Este es el único lugar que debes editar para personalizar el botón QR.
const fideliScannerConfig = ScannerUiConfig();
