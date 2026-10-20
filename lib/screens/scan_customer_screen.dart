import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/supabase_config.dart';
import '../models/app_data.dart';
import '../services/wallet_service.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';
import '../widgets/customer_avatar.dart';
import 'customers_screen.dart';

class ScanCustomerScreen extends StatefulWidget {
  const ScanCustomerScreen({super.key});

  @override
  State<ScanCustomerScreen> createState() => _ScanCustomerScreenState();
}

class _ScanCustomerScreenState extends State<ScanCustomerScreen> {
  static const _accent = FideliTheme.ink;
  final _controller = MobileScannerController();
  final _search = TextEditingController();
  bool _handling = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_handling || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    final parsed = _customer(raw);
    if (parsed == null) {
      showMessage(context, 'El QR no pertenece a Fideli');
      return;
    }
    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    final state = AppScope.of(context);
    // Antes de interpretar la tarjeta, trae la meta y los premios vigentes.
    // Así el escáner no abre una copia antigua después de editar un programa.
    await state.refreshFromCloud();
    if (!mounted) return;
    final customer = state.customerById(parsed.$1);
    if (customer == null) {
      showMessage(context, 'Cliente no encontrado en este dispositivo');
      _handling = false;
      if (mounted) await _controller.start();
      return;
    }
    await _openCustomer(customer, programId: parsed.$2, token: parsed.$3);
    _handling = false;
    if (mounted) await _controller.start();
  }

  (String, String?, String?)? _customer(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme == 'fideli' &&
        uri.host == 'customer' &&
        uri.pathSegments.isNotEmpty) {
      return (
        uri.pathSegments.first,
        uri.queryParameters['card'],
        uri.queryParameters['token'],
      );
    }
    final state = AppScope.of(context);
    final publicHost = Uri.parse(SupabaseConfig.publicClubUrl).host;
    final isTenantSubdomain = uri.host.endsWith('.$publicHost');
    final isPublicReferral =
        uri.scheme == 'https' &&
        (uri.host == publicHost || isTenantSubdomain) &&
        (isTenantSubdomain ||
            uri.queryParameters['business'] == state.cloudStore?.businessId);
    final customerId = uri.queryParameters['customer'];
    if (!isPublicReferral || customerId == null || customerId.isEmpty) {
      return null;
    }
    return (
      customerId,
      uri.queryParameters['card'],
      uri.queryParameters['token'],
    );
  }

  Future<void> _openCustomer(
    Customer customer, {
    String? programId,
    String? token,
  }) async {
    final data = AppScope.of(context).data;
    final requestedProgram = programId == null
        ? null
        : data.programs.where((item) => item.id == programId).firstOrNull;

    if (requestedProgram != null &&
        (requestedProgram.cardKind == 'Tarjeta de regalo' ||
            requestedProgram.cardKind == 'Membresía') &&
        (token == null || token.length < 32)) {
      showMessage(context, 'Código privado no válido');
      return;
    }
    if (requestedProgram != null &&
        (requestedProgram.cardKind == 'Tarjeta de regalo' ||
            requestedProgram.cardKind == 'Membresía')) {
      final validation = await WalletService().validatePrivateCardQr(
        data.business,
        customerId: customer.id,
        programId: requestedProgram.id,
        token: token!,
      );
      if (!validation.ok) {
        if (mounted) showMessage(context, validation.message);
        return;
      }
    }
    if (!mounted) return;

    if (requestedProgram?.cardKind == 'Membresía') {
      final status = requestedProgram!.isExpired
          ? 'Membresía vencida'
          : !requestedProgram.active ||
                !customer.cardBalances.containsKey(requestedProgram.id)
          ? 'Membresía bloqueada'
          : 'Membresía activa';
      showMessage(context, '${customer.name} · $status');
      return;
    }
    final activePrograms = data.programs
        .where((item) => item.active && !item.isExpired)
        .toList();
    final programs = data.activeProgramsForCustomer(customer);
    var selectedProgramId = programId;
    if (selectedProgramId != null &&
        !activePrograms.any((item) => item.id == selectedProgramId)) {
      showMessage(context, 'Esta tarjeta ya no está activa');
      return;
    }
    if (selectedProgramId != null &&
        !customer.cardBalances.containsKey(selectedProgramId)) {
      showMessage(context, 'Este cliente no pertenece a esta tarjeta');
      return;
    }
    if (selectedProgramId == null) {
      if (programs.isEmpty) {
        showMessage(context, 'Este cliente no tiene tarjetas activas');
        return;
      }
      if (programs.length == 1) {
        selectedProgramId = programs.first.id;
      } else {
        selectedProgramId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('¿Qué tarjeta quieres atender?'),
            children: [
              for (final program in programs)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, program.id),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(program.name),
                    subtitle: Text(
                      '${program.cardKind} · ${program.type.label}',
                    ),
                  ),
                ),
            ],
          ),
        );
        if (selectedProgramId == null || !mounted) return;
      }
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerServiceScreen(
          customerId: customer.id,
          programId: selectedProgramId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final data = AppScope.of(context).data;
    final goal =
        data.programs
            .where((item) => item.active && !item.isExpired)
            .firstOrNull
            ?.goal ??
        7;
    final customers = data.customers
        .where(
          (customer) =>
              query.isEmpty ||
              customer.name.toLowerCase().contains(query) ||
              customer.referralCode.toLowerCase().contains(query),
        )
        .toList();
    final scanner = _scannerPanel();
    final customerList = _customerList(
      query: query,
      customers: customers,
      goal: goal,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 30),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: scanner,
                        ),
                      ),
                    ),
                    const SizedBox(width: 34),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7F7),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: const Color(0x0F000000)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                          child: customerList,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
              children: [
                scanner,
                const SizedBox(height: 30),
                SizedBox(height: 520, child: customerList),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _scannerPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161313),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: .92,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _detected),
              const IgnorePointer(child: _ScannerShade()),
              Positioned(
                top: 14,
                right: 14,
                child: _CameraButton(
                  tooltip: _torchEnabled
                      ? 'Apagar linterna'
                      : 'Encender linterna',
                  icon: _torchEnabled
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  selected: _torchEnabled,
                  onPressed: () async {
                    await _controller.toggleTorch();
                    if (mounted) {
                      setState(() => _torchEnabled = !_torchEnabled);
                    }
                  },
                ),
              ),
              const Positioned(
                left: 24,
                right: 24,
                bottom: 20,
                child: _ScannerHint(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customerList({
    required String query,
    required List<Customer> customers,
    required int goal,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Buscar cliente',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'También puedes encontrarlo por nombre o código.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Color(0xFF817A78),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Nombre o código',
            hintStyle: const TextStyle(color: Color(0xFF98918F)),
            prefixIcon: const Icon(Icons.search_rounded, color: _accent),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar',
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0x0F000000)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: customers.isEmpty
              ? const Center(
                  child: Text(
                    'No se encontraron clientes',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF817A78),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 18),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return _CustomerResult(
                      customer: customer,
                      goal: goal,
                      onTap: () => _openCustomer(customer),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ScannerShade extends StatelessWidget {
  const _ScannerShade();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScannerShadePainter());
  }
}

class _ScannerShadePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.width * .67;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .46),
      width: scanSize,
      height: scanSize,
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(26)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = const Color(0x6B000000));

    const segment = 34.0;
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = RRect.fromRectAndRadius(scanRect, const Radius.circular(26));
    final path = Path()
      ..moveTo(r.left, r.top + segment)
      ..lineTo(r.left, r.top + 26)
      ..quadraticBezierTo(r.left, r.top, r.left + 26, r.top)
      ..lineTo(r.left + segment, r.top)
      ..moveTo(r.right - segment, r.top)
      ..lineTo(r.right - 26, r.top)
      ..quadraticBezierTo(r.right, r.top, r.right, r.top + 26)
      ..lineTo(r.right, r.top + segment)
      ..moveTo(r.right, r.bottom - segment)
      ..lineTo(r.right, r.bottom - 26)
      ..quadraticBezierTo(r.right, r.bottom, r.right - 26, r.bottom)
      ..lineTo(r.right - segment, r.bottom)
      ..moveTo(r.left + segment, r.bottom)
      ..lineTo(r.left + 26, r.bottom)
      ..quadraticBezierTo(r.left, r.bottom, r.left, r.bottom - 26)
      ..lineTo(r.left, r.bottom - segment);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? FideliTheme.ink : const Color(0x99000000),
        foregroundColor: Colors.white,
        minimumSize: const Size(46, 46),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class _ScannerHint extends StatelessWidget {
  const _ScannerHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB8000000),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Alinea el QR dentro del marco',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerResult extends StatelessWidget {
  const _CustomerResult({
    required this.customer,
    required this.goal,
    required this.onTap,
  });

  final Customer customer;
  final int goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              CustomerAvatar(customer: customer, size: 48),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${customer.stamps} de $goal sellos · ${customer.referralCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF817A78),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: FideliTheme.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
