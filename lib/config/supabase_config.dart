class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qdrssnhlbwkufnhgqfwo.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcnNzbmhsYndrdWZuaGdxZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4OTAyMzAsImV4cCI6MjA5NjQ2NjIzMH0.Y-P94zJJKx4n5L5f-23CoKFaQ3gP1ssvcKv6cn3uP1U',
  );
  static const publicClubUrl = String.fromEnvironment(
    'FIDELI_PUBLIC_CLUB_URL',
    defaultValue: 'https://fideli.site',
  );

  static Uri publicClubUriForBusiness(
    String businessId, {
    String publicSlug = '',
  }) {
    if (RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(publicSlug)) {
      return Uri.parse(publicClubUrl).replace(
        host: '$publicSlug.fideli.site',
        path: '/',
        queryParameters: {},
        fragment: '',
      );
    }
    return Uri.parse(
      publicClubUrl,
    ).replace(queryParameters: {'business': businessId});
  }

  static Uri publicStoreUriForBusiness(
    String businessId, {
    String publicSlug = '',
  }) {
    final club = publicClubUriForBusiness(businessId, publicSlug: publicSlug);
    if (publicSlug.isEmpty) {
      return club.replace(queryParameters: {'tienda': businessId});
    }
    return Uri(
      scheme: club.scheme,
      host: club.host,
      port: club.hasPort ? club.port : null,
      path: '/tienda',
    );
  }

  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;
  static String get walletFunctionUrl => '$url/functions/v1/wallet';
}
