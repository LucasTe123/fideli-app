import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class ShareClubScreen extends StatelessWidget {
  const ShareClubScreen({super.key});

  Uri? _clubUrl({String? cardId}) {
    final cloud = CloudStore.instance;
    if (cloud == null) return null;
    final base = SupabaseConfig.publicClubUriForBusiness(
      cloud.businessId,
      publicSlug: cloud.publicSlug,
    );
    final parameters = <String, String>{...base.queryParameters};
    if (cardId != null) parameters['card'] = cardId;
    return base.replace(queryParameters: parameters);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final business = state.data.business;
    final url = _clubUrl();
    final cards = state.data.programs
        .where((item) => item.active && !item.isExpired)
        .toList();
    return PageBody(
      children: [
        Text(
          'Compartir ${business.name}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Comparte el QR de la tarjeta que quieras ofrecer a tus clientes.',
        ),
        const SizedBox(height: 20),
        if (url == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'El servicio todavía no está disponible. Revisa tu conexión y vuelve a abrir Fideli.',
              ),
            ),
          )
        else ...[
          for (final card in cards)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      card.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    Text('${card.cardKind} · ${card.type.label}'),
                    const SizedBox(height: 14),
                    QrImageView(
                      data: _clubUrl(cardId: card.id)!.toString(),
                      size: 220,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: _clubUrl(cardId: card.id)!.toString(),
                              ),
                            );
                            if (context.mounted) {
                              showMessage(
                                context,
                                'Enlace de ${card.name} copiado',
                              );
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            _clubUrl(cardId: card.id)!,
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('Abrir'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (cards.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Primero crea y activa una tarjeta.'),
              ),
            ),
          ExpansionTile(
            title: const Text('Página general del comercio'),
            subtitle: const Text('Permite que la persona elija una tarjeta.'),
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    QrImageView(data: url.toString(), size: 200),
                    const SizedBox(height: 12),
                    SelectableText(url.toString(), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        const ListTile(
          leading: CircleAvatar(child: Text('1')),
          title: Text('Elige qué tarjeta compartir'),
          subtitle: Text('Sellos, puntos, membresía o regalo.'),
        ),
        const ListTile(
          leading: CircleAvatar(child: Text('2')),
          title: Text('La persona escanea ese QR'),
          subtitle: Text('Se abre únicamente el registro de esa tarjeta.'),
        ),
        const ListTile(
          leading: CircleAvatar(child: Text('3')),
          title: Text('Agrega su tarjeta'),
          subtitle: Text('Apple Wallet recibe el pase real del comercio.'),
        ),
      ],
    );
  }
}
