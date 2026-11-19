import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/cloud_store.dart';
import '../services/store_image.dart';

class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key});
  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  static const _serviceUrl = String.fromEnvironment(
    'WHATSAPP_SERVICE_URL',
    defaultValue: 'http://127.0.0.1:8790',
  );
  static const _green = Color(0xFF168C57);
  static const _ink = Color(0xFF26242B);
  static const _muted = Color(0xFF77747C);
  final _welcome = TextEditingController();
  final _catalog = TextEditingController();
  final _catalogMessage = TextEditingController(
    text: 'Te pasamos nuestro catálogo:',
  );
  final _instructions = TextEditingController();
  final _question = TextEditingController(
    text: 'Hola, ¿de qué tienda eres y dónde puedo ver tu catálogo?',
  );
  final Map<String, Uint8List> _photos = {};
  Timer? _poller;
  late final String _businessId;
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _status = {};
  bool _available = false, _polling = false, _loaded = false;
  bool _saving = false,
      _uploading = false,
      _previewing = false,
      _starting = false;
  bool _enabled = true, _dirty = false;
  int _tab = 0;
  String? _error, _preview;
  List<Map<String, dynamic>> get _media => ((_settings['media'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  String get _name =>
      _settings['business_name'] as String? ??
      _status['business_name'] as String? ??
      'tu negocio';
  String get _connection => _status['status'] as String? ?? 'idle';
  bool get _connected => _connection == 'connected';
  bool get _working =>
      ['starting', 'connecting', 'confirming'].contains(_connection);

  @override
  void initState() {
    super.initState();
    _businessId = CloudStore.instance?.currentUser?.id ?? '';
    _initialize();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poller?.cancel();
    for (final controller in [
      _welcome,
      _catalog,
      _catalogMessage,
      _instructions,
      _question,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<http.Response> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final cloud = CloudStore.instance;
    final token = cloud?.accessToken;
    if (_businessId.isEmpty ||
        token == null ||
        cloud?.currentUser?.id != _businessId) {
      throw StateError('Vuelve a iniciar sesión con la cuenta de tu negocio.');
    }
    final uri = Uri.parse('$_serviceUrl/api/whatsapp/$_businessId/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await request.send().timeout(
        Duration(seconds: path == 'preview' ? 150 : 50),
      ),
    );
    if (response.statusCode >= 400) {
      String message = 'No se pudo completar la solicitud.';
      try {
        final detail = (jsonDecode(response.body) as Map)['detail'];
        if (detail is String) message = detail;
        if (detail is List) {
          message =
              'Revisa los campos: el enlace debe comenzar con https:// y los textos deben respetar los límites.';
        }
      } catch (_) {
        /* Keep a readable message when the service is unavailable. */
      }
      throw StateError(message);
    }
    return response;
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : 'No se pudo conectar con el servicio de WhatsApp en este Mac.';
  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _initialize() async {
    try {
      final response = await _request('GET', 'settings');
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (!mounted) return;
      setState(() {
        _settings = data;
        _loaded = true;
        _available = true;
        _error = null;
        _welcome.text = data['welcome_message'] as String? ?? '';
        _catalog.text = data['catalog_url'] as String? ?? '';
        _catalogMessage.text =
            data['catalog_message'] as String? ??
            'Te pasamos nuestro catálogo:';
        _instructions.text = data['instructions'] as String? ?? '';
        _enabled = data['enabled'] == true;
      });
      await _refresh();
      for (final item in _media) {
        unawaited(_loadPhoto(item['id'] as String));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _available = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (_polling || !mounted) return;
    if (!_loaded) {
      _polling = true;
      try {
        await _initialize();
      } finally {
        _polling = false;
      }
      return;
    }
    _polling = true;
    try {
      final response = await _request('GET', 'status');
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (data['business_id'] != _businessId) {
        throw StateError('La conexión no pertenece a este negocio.');
      }
      if (mounted) {
        setState(() {
          _status = data;
          _available = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = false;
          _status = {};
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadPhoto(String id) async {
    if (_photos.containsKey(id)) return;
    try {
      final response = await _request('GET', 'media/$id');
      if (mounted) setState(() => _photos[id] = response.bodyBytes);
    } catch (_) {
      /* The card offers editing even if its thumbnail cannot load. */
    }
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await _request('PUT', 'settings', {
        'enabled': _enabled,
        'welcome_enabled': true,
        'welcome_message': _welcome.text.trim(),
        'catalog_enabled': true,
        'catalog_url': _catalog.text.trim(),
        'catalog_message': _catalogMessage.text.trim(),
        'instructions': _instructions.text.trim(),
      });
      if (!mounted) return false;
      setState(() {
        _settings = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        _dirty = false;
      });
      _notice('Configuración de $_name guardada.');
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      if (_dirty && !await _save()) return;
      await _request('POST', 'start');
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    try {
      await _request('POST', 'stop');
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _resetLink() async {
    setState(() => _starting = true);
    try {
      await _request('POST', 'reset-link');
      await _refresh();
      if (mounted) {
        setState(() {
          _status = {};
          _error = null;
        });
        _notice('Se olvidó el vínculo anterior. Ya puedes generar un QR nuevo.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _tryPrompt() async {
    if (_question.text.trim().isEmpty || _previewing) return;
    if (_dirty && !await _save()) return;
    if (!mounted) return;
    setState(() {
      _previewing = true;
      _preview = null;
      _error = null;
    });
    try {
      final response = await _request('POST', 'preview', {
        'prompt': _question.text.trim(),
      });
      final data = jsonDecode(response.body) as Map;
      if (mounted) setState(() => _preview = data['reply'] as String?);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _editImage([Map<String, dynamic>? existing]) async {
    Uint8List? bytes;
    if (existing == null) {
      try {
        bytes = await pickStoreImage();
      } catch (error) {
        _notice(_message(error));
        return;
      }
      if (bytes == null || !mounted) return;
    } else {
      bytes = _photos[existing['id']];
    }
    final title = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    final caption = TextEditingController(
      text: existing?['caption'] as String? ?? '',
    );
    final keywords = TextEditingController(
      text: existing?['keywords'] as String? ?? '',
    );
    var onWelcome = existing?['send_on_welcome'] == true;
    var enabled = existing?['enabled'] != false;
    final metadata = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Agregar imagen' : 'Editar imagen'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        bytes,
                        height: 150,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: title,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la imagen',
                      hintText: 'Ej. Menú de desayunos',
                    ),
                  ),
                  TextField(
                    controller: caption,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje que acompaña la foto',
                    ),
                  ),
                  TextField(
                    controller: keywords,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Cuándo ofrecerla',
                      hintText: 'Ej. desayunos, café, menú',
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enviar con la bienvenida'),
                    subtitle: const Text(
                      'Se envían hasta dos fotos por bienvenida.',
                    ),
                    value: onWelcome,
                    onChanged: (v) => update(() => onWelcome = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponible para el bot'),
                    value: enabled,
                    onChanged: (v) => update(() => enabled = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'title': title.text.trim(),
                  'caption': caption.text.trim(),
                  'keywords': keywords.text.trim(),
                  'send_on_welcome': onWelcome,
                  'enabled': enabled,
                });
              },
              child: const Text('Guardar imagen'),
            ),
          ],
        ),
      ),
    );
    // Dialog route animations may still reference these controllers briefly.
    Future<void>.delayed(const Duration(seconds: 1), () {
      title.dispose();
      caption.dispose();
      keywords.dispose();
    });
    if (metadata == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      if (existing == null) {
        final response = await _request('POST', 'media', {
          ...metadata,
          'data': base64Encode(bytes!),
        });
        final item = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map,
        );
        if (!mounted) return;
        setState(() {
          _settings['media'] = [..._media, item];
          _photos[item['id'] as String] = bytes!;
        });
      } else {
        await _request('PATCH', 'media/${existing['id']}', metadata);
        if (mounted) {
          setState(
            () => _settings['media'] = _media
                .map(
                  (m) => m['id'] == existing['id']
                      ? {...metadata, 'id': m['id']}
                      : m,
                )
                .toList(),
          );
        }
      }
      _notice('Imagen guardada para $_name.');
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeImage(String id) async {
    try {
      await _request('DELETE', 'media/$id');
      if (mounted) {
        setState(() {
          _settings['media'] = _media.where((m) => m['id'] != id).toList();
          _photos.remove(id);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String get _statusLabel => !_available
      ? 'Servicio local sin conexión'
      : switch (_connection) {
          'connected' => 'Conectado',
          'pairing' => 'Escanea el QR con tu teléfono',
          'starting' || 'connecting' => 'Conectando…',
          'confirming' => 'Confirmando la sesión…',
          'error' => 'No se pudo conectar',
          _ => 'Desconectado',
        };

  Widget _card(String title, String subtitle, Widget child, {IconData? icon}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8E6E9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: _green),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, height: 1.5),
              ),
            ],
            const SizedBox(height: 20),
            child,
          ],
        ),
      );

  Widget _connectionPanel() => _card(
    'Conexión de $_name',
    'Esta sesión de WhatsApp pertenece únicamente a este negocio.',
    Column(
      children: [
        if (_connection == 'pairing' && _status['qr'] != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE8E6E9)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: _status['qr'] as String,
              size: 240,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Abre WhatsApp → Dispositivos vinculados → Vincular un dispositivo y escanea el código.',
            textAlign: TextAlign.center,
          ),
        ] else if (_connected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8F2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(Icons.verified_rounded, color: _green, size: 36),
                const SizedBox(height: 12),
                Text(
                  'WhatsApp de $_name está conectado',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _enabled
                      ? 'El bot envía la bienvenida y luego el catálogo a cada mensaje nuevo.'
                      : 'Las respuestas automáticas están pausadas.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Mensajes recibidos: ${_status['messages_received'] ?? 0} · Envíos confirmados: ${_status['outbound_accepted'] ?? 0}',
                  style: const TextStyle(color: _muted),
                ),
                if (_status['ai_status'] == 'generating' ||
                    _status['ai_status'] == 'sending') ...[
                  const SizedBox(height: 10),
                  Text(
                    _status['ai_status'] == 'generating'
                        ? 'Gemini está preparando una respuesta…'
                        : 'Enviando la respuesta por WhatsApp…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _green),
                  ),
                ],
              ],
            ),
          )
        else if (_working)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: _green),
          )
        else
          const Text(
            'Vincula el número de WhatsApp que utilizará este negocio para atender a sus clientes.',
          ),
        if (_status['error'] != null) ...[
          const SizedBox(height: 12),
          Text(
            _status['error'].toString(),
            style: const TextStyle(color: Colors.red),
          ),
        ],
        if (_status['ai_error'] != null) ...[
          const SizedBox(height: 12),
          Text(
            _status['ai_error'].toString(),
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                !_available ||
                    _starting ||
                    _connected ||
                    _working ||
                    _connection == 'pairing'
                ? null
                : _start,
            icon: const Icon(Icons.qr_code_2),
            label: Text(
              _connected
                  ? 'WhatsApp conectado'
                  : _connection == 'pairing'
                  ? 'Esperando el escaneo…'
                  : 'Vincular WhatsApp',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              disabledBackgroundColor: _green.withValues(alpha: .15),
              disabledForegroundColor: _green,
              padding: const EdgeInsets.all(18),
            ),
          ),
        ),
        if (_connected)
          TextButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.pause_circle_outline),
            label: const Text('Detener el bot en este Mac'),
          ),
        TextButton.icon(
          onPressed: !_available || _starting ? null : _resetLink,
          icon: const Icon(Icons.link_off),
          label: const Text('Olvidar vínculo y generar un QR nuevo'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mantén este Mac encendido para recibir y responder mensajes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
    icon: PhosphorIcons.whatsappLogoFill,
  );

  Widget _messagesPanel() => Column(
    children: [
      _card(
        'Atención automática',
        'Elige cómo responderá el WhatsApp de $_name.',
        Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Responder mensajes de clientes'),
              subtitle: const Text(
                'Puedes pausar las respuestas sin cerrar la sesión de WhatsApp.',
              ),
              value: _enabled,
              onChanged: (v) => setState(() {
                _enabled = v;
                _dirty = true;
              }),
            ),
          ],
        ),
        icon: Icons.auto_awesome_outlined,
      ),
      const SizedBox(height: 18),
      _card(
        'Mensaje de bienvenida',
        'Se envía cada vez que un cliente escribe, como primer mensaje.',
        Column(
          children: [
            TextField(
              controller: _welcome,
              maxLength: 1600,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                labelText: 'Tu saludo',
                hintText: '¡Hola! Bienvenido a {negocio}.',
                border: OutlineInputBorder(),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Usa {negocio} para insertar el nombre de tu tienda.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          ],
        ),
        icon: Icons.waving_hand_outlined,
      ),
      const SizedBox(height: 18),
      _card(
        'Link del catálogo',
        'Se envía en otro mensaje, después de la bienvenida.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _catalogMessage,
              maxLength: 1600,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                labelText: 'Mensaje del catálogo',
                hintText: 'Te pasamos nuestro catálogo:',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _catalog,
              keyboardType: TextInputType.url,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                labelText: 'Enlace de catálogo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _catalog.text = _settings['store_url'] as String? ?? '';
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Usar mi tienda de Fideli'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _catalog.text));
                    _notice('Enlace copiado.');
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar enlace'),
                ),
              ],
            ),
          ],
        ),
        icon: Icons.link,
      ),
    ],
  );

  Widget _imagesPanel() => _card(
    'Imágenes de $_name',
    'Agrega fotos, menús o promociones. El bot podrá enviarlas según lo que pida el cliente. Hasta 8 imágenes.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _uploading || _media.length >= 8
              ? null
              : () => _editImage(),
          icon: _uploading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(_uploading ? 'Guardando imagen…' : 'Agregar imagen'),
        ),
        const SizedBox(height: 16),
        if (_media.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              children: [
                Icon(Icons.photo_library_outlined, size: 42, color: _muted),
                SizedBox(height: 10),
                Text(
                  'Tu galería está lista para agregar imágenes.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 560
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _media
                  .map(
                    (image) => SizedBox(
                      width: width,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE8E6E9)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                              child: AspectRatio(
                                aspectRatio: 1.8,
                                child: _photos[image['id']] == null
                                    ? const ColoredBox(
                                        color: Color(0xFFF5F3F6),
                                        child: Icon(
                                          Icons.image_outlined,
                                          color: _muted,
                                        ),
                                      )
                                    : Image.memory(
                                        _photos[image['id']]!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    image['title'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if ((image['caption'] as String? ?? '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      image['caption'] as String,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: _muted),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    image['enabled'] == false
                                        ? 'Pausada'
                                        : image['send_on_welcome'] == true
                                        ? 'Bienvenida y consultas'
                                        : 'Según la consulta',
                                    style: const TextStyle(
                                      color: _green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar imagen',
                                        onPressed: _uploading
                                            ? null
                                            : () => _editImage(image),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Quitar del bot',
                                        onPressed: () =>
                                            _removeImage(image['id'] as String),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
    icon: Icons.photo_library_outlined,
  );

  Widget _instructionsPanel() => Column(
    children: [
      _card(
        'Instrucciones del negocio',
        'Define cómo quieres que el bot atienda a los clientes de $_name.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF8F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'El bot ya conoce el nombre de $_name, su categoría, los productos publicados y el enlace de su tienda.',
                style: const TextStyle(color: _green, height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _instructions,
              maxLength: 6000,
              minLines: 7,
              maxLines: 14,
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(
                labelText: 'Cómo debe atender',
                alignLabelWithHint: true,
                hintText:
                    'Ejemplo: Habla de forma cercana y breve.\nHorario: lunes a sábado de 9:00 a 20:00.\nSi preguntan por una reserva, indica cómo contactar al negocio.\nOfrece la foto del menú cuando pidan opciones.',
                border: OutlineInputBorder(),
              ),
            ),
            const Text(
              'Agrega horarios, ubicación, estilo de respuesta y condiciones. El bot no confirma pagos, pedidos ni reservas.',
              style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
            ),
          ],
        ),
        icon: Icons.tune,
      ),
      const SizedBox(height: 18),
      _card(
        'Probar una respuesta',
        'Consulta a Gemini con la configuración guardada de $_name. La prueba se muestra aquí.',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _question,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Mensaje del cliente',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _previewing ? null : _tryPrompt,
              icon: _previewing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _previewing ? 'Preparando respuesta…' : 'Probar con Gemini',
              ),
            ),
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F0F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SelectableText(
                  _preview!,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ],
          ],
        ),
        icon: Icons.chat_bubble_outline,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF8F8F7),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: .10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIcons.whatsappLogoFill,
                    color: _green,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp de $_name',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _connected && _available
                                ? Icons.check_circle
                                : Icons.circle,
                            size: 12,
                            color: _connected && _available ? _green : _muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _statusLabel,
                              style: const TextStyle(color: _muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in [
                    (0, 'Conexión', Icons.link),
                    (1, 'Mensajes', Icons.chat_bubble_outline),
                    (2, 'Imágenes', Icons.image_outlined),
                    (3, 'Instrucciones', Icons.tune),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _tab == item.$1,
                        avatar: Icon(
                          item.$3,
                          size: 17,
                          color: _tab == item.$1 ? _green : _muted,
                        ),
                        showCheckmark: false,
                        label: Text(item.$2),
                        labelStyle: TextStyle(
                          color: _tab == item.$1 ? _green : _ink,
                          fontWeight: FontWeight.w600,
                        ),
                        selectedColor: const Color(0xFFDFF2E7),
                        onSelected: (_) => setState(() => _tab = item.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFF9C3333)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!_loaded)
              _card(
                'Preparando WhatsApp',
                'Cargando la configuración de tu cuenta de Fideli.',
                Column(
                  children: [
                    if (_error == null)
                      const CircularProgressIndicator(color: _green),
                    if (_error != null)
                      TextButton(
                        onPressed: _initialize,
                        child: const Text('Reintentar'),
                      ),
                  ],
                ),
              )
            else ...[
              switch (_tab) {
                0 => _connectionPanel(),
                1 => _messagesPanel(),
                2 => _imagesPanel(),
                _ => _instructionsPanel(),
              },
              if (_tab != 0) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dirty
                            ? 'Cambios sin guardar'
                            : 'Configuración de $_name',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving || !_available ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.all(18),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
