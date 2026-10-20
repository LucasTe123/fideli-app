import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/supabase_config.dart';
import '../models/app_data.dart';
import '../services/cloud_store.dart';
import 'common.dart';

Uri? programEnrollmentUrl(String programId) {
  final cloud = CloudStore.instance;
  if (cloud == null || cloud.businessId.isEmpty) return null;
  final base = SupabaseConfig.publicClubUriForBusiness(
    cloud.businessId,
    publicSlug: cloud.publicSlug,
  );
  return base.replace(
    queryParameters: {...base.queryParameters, 'card': programId},
  );
}

Future<void> showProgramQrSheet(
  BuildContext context,
  LoyaltyProgram program,
) async {
  final url = programEnrollmentUrl(program.id);
  if (url == null) {
    showMessage(context, 'Conecta el negocio para generar el QR');
    return;
  }

  await showAppleBottomSheet<void>(
    context,
    builder: (sheetContext, scrollController) => _ProgramQrContent(
      program: program,
      url: url,
      scrollController: scrollController,
    ),
  );
}

class _ProgramQrContent extends StatefulWidget {
  const _ProgramQrContent({
    required this.program,
    required this.url,
    required this.scrollController,
  });

  final LoyaltyProgram program;
  final Uri url;
  final ScrollController scrollController;

  @override
  State<_ProgramQrContent> createState() => _ProgramQrContentState();
}

class _ProgramQrContentState extends State<_ProgramQrContent> {
  final GlobalKey _imageKey = GlobalKey();
  bool _working = false;

  String get _fileName {
    final normalized = widget.program.name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return 'qr-${normalized.isEmpty ? widget.program.id : normalized}';
  }

  Future<Uint8List> _renderImage() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _imageKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('El QR todavía no está listo');
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('No se pudo crear la imagen del QR');
    return data.buffer.asUint8List();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showMessage(context, 'No se pudo preparar el QR');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _share() => _run(() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(
        // Compartir debe entregar únicamente el enlace de esta tarjeta. El QR
        // como imagen se conserva exclusivamente para la acción Descargar.
        text: widget.url.toString(),
        sharePositionOrigin: origin,
      ),
    );
  });

  Future<void> _download() => _run(() async {
    final bytes = await _renderImage();
    await FileSaver.instance.saveAs(
      name: _fileName,
      bytes: bytes,
      fileExtension: 'png',
      mimeType: MimeType.png,
    );
    if (mounted) showMessage(context, 'QR guardado');
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 44),
                  Expanded(
                    child: Text(
                      widget.program.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _imageKey,
                child: Container(
                  width: 330,
                  padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.program.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D2829),
                        ),
                      ),
                      const SizedBox(height: 18),
                      QrImageView(
                        data: widget.url.toString(),
                        version: QrVersions.auto,
                        size: 250,
                        gapless: false,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Escanea para agregar tu tarjeta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF756E6C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _working ? null : _share,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Compartir'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _working ? null : _download,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Descargar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_working) ...[
                const SizedBox(height: 16),
                const CupertinoActivityIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
