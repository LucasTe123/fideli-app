# Fideli

## Inteligencia de clientes

La app incluye una primera fase productiva de Customer Intelligence: eventos
estructurados, métricas de recencia/frecuencia/valor, cadencia adaptativa,
segmentos explicables, historial y audiencias dinámicas de campañas. La guía de
arquitectura y despliegue está en
[`docs/customer-intelligence.md`](docs/customer-intelligence.md).

Fideli es una app Flutter para que un comercio gestione un club de fidelización conectado con Apple Wallet y Google Wallet. No incluye CRM, inventario ni facturación.

## Qué funciona

- Onboarding y configuración del negocio, sucursales, color y URL del backend.
- Dashboard y actividad reciente.
- Varias tarjetas simultáneas: fidelización, membresía o regalo; cada una mantiene su propio saldo y configuración.
- Saldo, visitas, meta, QR e identificador Wallet independientes por tarjeta.
- Clientes, niveles automáticos, recompensas, canjes, retos y referidos.
- Campañas reales por público.
- Estadísticas básicas.
- QR personal real por cliente y escáner con cámara.
- Vista cliente/club.
- Wallet Studio y vista previa.
- Canal nativo iOS con `PKPass` + `PKAddPassesViewController`.
- Backend permanente en Supabase Edge Functions que firma `.pkpass`, implementa actualizaciones PassKit/APNs y deja listo el JWT de Google Wallet.
- Base central Supabase con RLS y copia local con `SharedPreferences` para seguir trabajando sin conexión.
- Modo demo claro cuando aún no hay credenciales.
- Sincronización automática de clientes, puntos, sellos, visitas y configuración del comercio.
- Pantalla **Compartir cafetería** con QR público: una persona se registra, aparece en el dashboard y descarga su propio pase Apple Wallet.
- Vencimiento real de pases mediante `expirationDate`, anulación remota y baja individual o masiva de clientes.
- Programas, recompensas, niveles y campañas normalizados en Supabase, además del respaldo local.

## Estructura

```text
lib/
  config/
    scanner_ui_config.dart       apariencia y apertura del botón QR
    supabase_config.dart         conexión pública con Supabase
  models/                        datos y serialización
  state/                         reglas del negocio y persistencia
  services/                      almacenamiento y adaptadores Wallet
  screens/
    dashboard_screen.dart        Dashboard
    business_screen.dart         Mi negocio
    share_club_screen.dart       Compartir cafetería
    wallet_studio_screen.dart    Wallet Studio
    programs_screen.dart         Programas
    customers_screen.dart        Clientes y detalle del cliente
    campaigns_screen.dart        Campañas
    navigation_menu_screen.dart  menú principal
    scan_customer_screen.dart    cámara y búsqueda para atender clientes
  widgets/
    scanner_action_button.dart   botón QR global reutilizable
    common.dart                  componentes compartidos
backend/
  server.js     servidor local alternativo para desarrollo sin Supabase
  assets/       imágenes mínimas del pase
  certs/        carpeta ignorada para certificados locales
test/           flujo funcional y smoke test
supabase/
  migrations/   base de datos y políticas RLS
  functions/    servicio público Apple Wallet / Google Wallet
club-site/      formulario público de alta conectado con Supabase
```

### Personalizar el escáner QR

Edita únicamente `lib/config/scanner_ui_config.dart`. Allí se controlan:

- `color`: color del botón;
- `foregroundColor`: color del símbolo;
- `icon`: icono de Material que se muestra;
- `shape`: `circle`, `roundedSquare` o `pill`;
- `openMode`: `fullScreen` o `bottomSheet`;
- `screenTitle`: título de la pantalla;
- `size`: tamaño del botón.

El menú muestra el botón global mediante `ScannerActionButton`. Si en el futuro se necesita sustituir completamente la experiencia de escaneo, el parámetro `scannerBuilder` permite conectar otra pantalla sin modificar la navegación.

## 1. Ejecutar Flutter

Requisitos: Flutter estable, Xcode completo, iOS 15 o posterior y una cuenta Apple iniciada en Xcode.

```bash
flutter pub get
flutter doctor -v
flutter analyze
flutter test
```

En este Mac el proyecto está dentro de Documents/File Provider. Si Xcode muestra `resource fork, Finder information, or similar detritus not allowed`, compila fuera de File Provider mediante un enlace local:

```bash
mv build /private/tmp/fideli-build-anterior 2>/dev/null || true
mkdir -p /private/tmp/fideli-build
ln -s /private/tmp/fideli-build build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build ios
```

Si `flutter doctor` indica que están seleccionadas solo las Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

## 2. Instalar en un iPhone de prueba

1. Conecta el iPhone por cable, desbloquéalo y acepta **Confiar en este ordenador**.
2. Activa **Modo de desarrollador** en `Ajustes > Privacidad y seguridad > Modo de desarrollador` si iOS lo solicita.
3. Abre `ios/Runner.xcworkspace` en Xcode.
4. En `Runner > Signing & Capabilities`, selecciona tu Team y cambia el Bundle Identifier si `app.fideli.fideli` no es único.
5. Selecciona tu iPhone como destino y pulsa Run, o usa:

```bash
flutter devices
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d ID_DEL_IPHONE --release
```

Una cuenta Apple personal gratuita sirve para ejecutar la app en un dispositivo de prueba. La emisión de pases requiere el Pass Type ID y certificado correspondientes de Apple Developer.

## 3. Backend local en modo demo

No hay que instalar paquetes npm; usa solo módulos incluidos en Node.js 20+.

```bash
cd backend
node server.js
```

Comprueba en otra terminal:

```bash
curl http://localhost:8787/health
```

En el simulador iOS puedes usar `http://localhost:8787`. En un iPhone físico, el teléfono y el Mac deben estar en la misma Wi-Fi. Obtén la IP del Mac con:

```bash
ipconfig getifaddr en0
```

En **Mi negocio > URL del backend Wallet**, escribe por ejemplo `http://192.168.1.50:8787`. La configuración iOS permite HTTP local únicamente para facilitar el MVP; antes de publicar, usa HTTPS y elimina `NSAllowsArbitraryLoads` de `ios/Runner/Info.plist`.

## 3A. Backend permanente en Supabase

La versión de producción usa Supabase como fuente central y conserva `SharedPreferences` únicamente como respaldo sin conexión.

El proyecto de prueba actual ya está desplegado en:

```text
https://qdrssnhlbwkufnhgqfwo.supabase.co/functions/v1/wallet
```

`lib/config/supabase_config.dart` ya apunta a este proyecto. El pase de prueba se validó como `.pkpass` firmado y el servicio informa Apple real + actualizaciones automáticas activas.

- `supabase/migrations/` contiene comercios, miembros, clientes, historial de actividad y registros PassKit con RLS.
- `supabase/functions/wallet/` reemplaza al servidor Node local: genera `.pkpass`, implementa el servicio de actualización de Apple y envía APNs.
- `lib/services/cloud_store.dart` sincroniza todos los módulos de Fideli y mantiene el snapshot completo del comercio.
- `lib/config/supabase_config.dart` contiene solamente la URL y clave publicable; nunca contiene certificados ni claves privadas.

Para desplegar en otro proyecto:

```bash
npx supabase@latest login
npx supabase@latest link --project-ref TU_PROJECT_REF
npx supabase@latest db push
npx supabase@latest functions deploy wallet --no-verify-jwt
```

Configura como secretos de la Edge Function:

```text
APPLE_PASS_TYPE_ID
APPLE_TEAM_ID
APPLE_WWDR_CERT_PEM
APPLE_SIGNER_CERT_PEM
APPLE_SIGNER_KEY_PEM
APPLE_APNS_KEY_ID
APPLE_APNS_PRIVATE_KEY
GOOGLE_ISSUER_ID
GOOGLE_CLASS_SUFFIX
GOOGLE_SERVICE_ACCOUNT_JSON
GOOGLE_LOGO_URL
```

Apple llama directamente a `https://TU_PROJECT_REF.supabase.co/functions/v1/wallet/v1/...`. La función valida el `authenticationToken`; las operaciones del comercio además exigen la sesión Supabase del vendedor.

La página de registro del cliente vive separada del API porque Supabase no permite servir HTML desde Edge Functions en su dominio compartido. Fideli muestra el enlace desde **Dashboard > Compartir cafetería**. El formulario consulta y registra clientes mediante la Edge Function; al terminar entrega el `.pkpass` firmado.

## 4. Crear un pase Apple Wallet real

Apple exige que el pase sea un paquete firmado. La clave privada queda en el backend.

1. En Apple Developer, crea un **Pass Type ID** (por ejemplo `pass.com.tuempresa.fideli`).
2. Crea un certificado para ese Pass Type ID, descárgalo y expórtalo junto con su clave privada desde Keychain como `.p12`.
3. Descarga el certificado intermedio WWDR vigente desde Apple.
4. Convierte los archivos a PEM en una carpeta privada fuera del repositorio:

```bash
openssl x509 -inform DER -in pass.cer -out pass-certificate.pem
openssl pkcs12 -in pass.p12 -nocerts -nodes -out pass-private-key.pem
openssl x509 -inform DER -in AppleWWDRCAG4.cer -out AppleWWDRCAG4.pem
chmod 600 pass-private-key.pem
```

5. Para Supabase, carga los PEM como secretos cifrados con `supabase secrets set`; no los copies al proyecto.
6. Despliega `supabase/functions/wallet`. `/health` debe devolver `"apple": true` y `"appleAutomaticUpdates": true`.
7. En Fideli crea un cliente y abre su detalle. El cliente escanea **Entregar tarjeta Apple Wallet** con su propio iPhone y agrega el pase. El backend genera `pass.json`, manifiesto SHA-1, firma PKCS#7 y `.pkpass`.

Para actualizar pases ya instalados, la Edge Function usa su URL HTTPS estable. Implementa el servicio web de PassKit (`/v1/devices`, `/v1/passes` y `/v1/log`), guarda los dispositivos registrados y envía la notificación APNs cuando la app registra un cambio. El pase instalado se vuelve a descargar y actualiza sin agregarlo otra vez.

## Tarjetas, vencimientos y bajas

En **Tarjetas** se pueden crear varias definiciones activas. Cada una tiene nombre, clase, sistema de acumulación, tasa, meta y fecha opcional de vencimiento. La página pública muestra las tarjetas vigentes para que el cliente elija cuál agregar. Los pases usan seriales separados y conservan saldos independientes.

En **Compartir cafetería**, cada tarjeta activa tiene su propio QR y URL de registro. Una página de sellos solo explica y registra sellos; puntos usa puntos; membresía muestra vigencia y regalo usa saldo monetario. La página general del comercio continúa disponible como opción secundaria para permitir que el cliente elija.

Al atender manualmente a un cliente con varias tarjetas, Fideli obliga a elegir primero la tarjeta presentada. Así se evita usar por accidente los controles de regalo en una tarjeta de sellos. Únicamente **Tarjeta de regalo** muestra **Cargar saldo** y **Consumir saldo**.

Al llegar la fecha, Apple Wallet reconoce `expirationDate` y muestra el pase como vencido. Si el comercio anula una tarjeta o borra un cliente, Fideli marca el pase con `voided: true`, actualiza su registro y envía APNs. Apple no permite que un comercio borre físicamente un pase del Wallet ajeno; anularlo es el mecanismo oficial y evita que siga siendo válido.

En **Clientes** existe borrado individual y **Borrar todos**, ambos con confirmación. Las filas se dan de baja de forma lógica para que el servicio de Wallet todavía pueda entregar la actualización de anulación, pero dejan de aparecer en la app, estadísticas y campañas.

### Automatizaciones

Una automatización es una regla de saldo, no una notificación. En el MVP se configura con tres elecciones cerradas: el evento (`Nuevo cliente` o `Cada visita`), la acción (`Dar puntos` o `Dar sellos`) y la cantidad. Por ejemplo, `Nuevo cliente → Dar 25 puntos` se ejecuta una sola vez al crear al cliente, tanto desde Fideli como desde la página pública. `Cada visita → Dar 2 sellos` se ejecuta al registrar la visita mediante el escáner.

Las reglas de texto libre creadas por versiones anteriores se muestran como no válidas y deben borrarse y recrearse. Los mensajes que deben aparecer en Apple Wallet se envían desde **Campañas**.

### Referidos y QR compartible

El QR de cada tarjeta usa una URL pública con el comercio, cliente referente, código y tarjeta. El mismo QR tiene dos usos: la cámara normal abre el formulario público con la invitación ya vinculada, mientras el escáner de Fideli identifica al cliente y abre su pantalla de atención. Si una persona nueva completa el registro, el referente recibe 50 puntos, se guarda el movimiento y se solicita la actualización de sus pases Wallet. La tarjeta explica **Comparte tu QR · Invita y gana 50 puntos**.

El premio se entrega solamente en un alta nueva; volver a abrir el enlace o registrar un correo/teléfono que ya existe no vuelve a premiar al referente.

### Notificaciones de Wallet

- En **Mi negocio**, el comercio puede elegir una foto o logo. Fideli la recorta, convierte a PNG y sube en los tamaños `icon.png`, `icon@2x.png` e `icon@3x.png` a un bucket privado de Supabase. El backend incorpora esos archivos en los pases de ese comercio.
- **Campañas** conserva una interfaz comercial simple. Internamente envía la actualización mediante Apple Wallet y utiliza el icono propio del comercio; no muestra indicadores ni configuración técnica de canales.
- Al sumar o quitar sellos y registrar visitas, Fideli sincroniza al cliente, avisa a Apple mediante APNs y Wallet descarga el pase actualizado.
- Los campos dinámicos incluyen `changeMessage`, por lo que iPhone puede mostrar el nuevo número de sellos, visitas o estado de la recompensa.
- En **Campañas**, crea un borrador, elige el público y pulsa **Enviar**. El mensaje queda como **NOVEDAD** en la tarjeta y el resultado indica cuántos clientes fueron seleccionados y cuántos Wallet recibieron la actualización.
- Los públicos disponibles en el MVP son todos, nivel Bronce/Plata/Oro/VIP e inactivos (clientes con cero visitas).
- La prueba desplegada el 23 de septiembre de 2026 fue aceptada por APNs para los Wallet registrados.

iOS controla la presentación final del aviso. El usuario debe conservar la tarjeta instalada y permitir las notificaciones de Wallet; Fideli no necesita volver a instalar el pase.

Los identificadores Apple, credenciales, estado del backend y modo de demostración son configuración privada de la plataforma. No aparecen en Wallet Studio ni en Mi negocio. Wallet Studio no muestra la lista de programas: ofrece únicamente los dos diseños generales definidos para el comercio, **Tarjeta de sellos** y **Membresía**. El color o la fotografía elegidos se aplican conjuntamente a todas las tarjetas del tipo correspondiente. La foto se recorta al formato panorámico de Wallet y se guarda en versiones `strip.png`, `strip@2x.png` y `strip@3x.png` dentro del almacenamiento privado del comercio.

La edición utiliza un borrador local. Al pulsar **Editar**, los cambios de color y fotografía se ven inmediatamente en la vista previa sin consultar Supabase. **Cancelar** descarta el borrador y **Aplicar cambios** realiza una sola subida y sincronización con los pases existentes.

Antes de incorporar una fotografía, Wallet Studio abre un recortador interactivo con el marco bloqueado en la proporción de Apple Wallet. La imagen se puede desplazar y ampliar con gestos. La medida de diseño recomendada es **1125 × 369 px**; la aplicación también genera automáticamente las variantes **750 × 246 px** y **375 × 123 px**.

Para las tarjetas de sellos, Wallet Studio permite elegir el símbolo visual del progreso: café, pizza, peluquería, estrella, corazón, mascotas o sello clásico. No se utilizan emojis: el backend dibuja iconos vectoriales monocromáticos, blancos para los sellos obtenidos y semitransparentes para los pendientes, además del contador. La imagen del negocio se procesa en dos formatos separados: logo horizontal para la parte superior del pase y símbolo cuadrado para Wallet y sus notificaciones.

Cada vez que se cambia el icono del comercio o el fondo de una tarjeta se crea una ruta de imagen nueva. Esto evita que Apple Wallet, Supabase o una red intermedia reutilicen la fotografía anterior. Después de guardar, el backend marca los pases existentes como actualizados y envía la actualización a los dispositivos registrados; el cliente no debe volver a agregar su tarjeta.

La tabla de clientes está incluida en Supabase Realtime. Las altas realizadas desde la página pública aparecen automáticamente en la aplicación, sin recargarla. Los movimientos de sellos son optimistas: la cifra cambia inmediatamente en pantalla y la sincronización con Supabase y Apple Wallet continúa en segundo plano. La migración de datos también recupera saldos antiguos que estaban guardados globalmente pero todavía no figuraban en el saldo individual de la tarjeta.

Importante: la URL debe ser pública, usar HTTPS válido y mantenerse estable. Después de configurarla hay que emitir una vez un pase nuevo, porque un pase instalado antes de definir `PUBLIC_BASE_URL` no conoce el servicio de actualización.

El flujo normal del vendedor es: escanear el QR o buscar nombre/código → **+1 sello y registrar visita**. La pantalla de vendedor no contiene un botón para reinstalar o actualizar Wallet.

Para la sugerencia por proximidad, configura `STORE_LATITUDE`, `STORE_LONGITUDE` y `STORE_RELEVANT_TEXT`. Apple decide cuándo mostrar la sugerencia en la pantalla bloqueada; la distancia exacta no puede fijarse en 100 metros.

## 5. Configurar Google Wallet real

1. Habilita Google Wallet API y solicita/activa una cuenta emisora.
2. Crea una Service Account, autorízala en Google Pay & Wallet Console y descarga el JSON.
3. Guarda el JSON fuera del repositorio.
4. Carga estos secretos cifrados en Supabase:

```text
GOOGLE_ISSUER_ID=tu_issuer_id
GOOGLE_CLASS_SUFFIX=fideli_loyalty
GOOGLE_SERVICE_ACCOUNT_JSON={contenido completo del JSON}
GOOGLE_LOGO_URL=https://qdrssnhlbwkufnhgqfwo.supabase.co/functions/v1/wallet/assets/icon.png
```

`GOOGLE_LOGO_URL` debe ser una imagen HTTPS accesible públicamente. El backend expone `/assets/icon.png`, por lo que puedes usar esa ruta detrás de tu dominio HTTPS.

5. Vuelve a desplegar la Edge Function. `/health` debe devolver `"google": true`.
6. Entrega el enlace de alta al cliente desde un canal/vista de cliente. El dashboard del vendedor no debe agregar la tarjeta a su propio teléfono. El backend firma un JWT RS256 con `LoyaltyClass` + `LoyaltyObject` y genera el enlace `https://pay.google.com/gp/v/save/...`.

Durante desarrollo la clase se crea con `UNDER_REVIEW`. La aprobación/publicación final se gestiona en Google Wallet Console.

## Seguridad

- Nunca copies `.p12`, PEM ni Service Account dentro de `lib/`, assets Flutter o control de versiones.
- `backend/.env`, `backend/certs/`, PEM, P12 y JSON de Service Account están ignorados por Git.
- La sesión MVP se crea de forma anónima en Supabase. Antes de publicar comercialmente debe reemplazarse por login verificado, recuperación de cuenta y facturación.
- Supabase aplica RLS por comercio; solo propietarios/gerentes pueden administrar membresías del equipo.
- Las campañas manuales ya se envían a todas las tarjetas instaladas de cada cliente seleccionado. La ejecución automática por horario todavía requiere un cron de producción.
- El backend local acepta parámetros de prueba sin autenticar. No debe exponerse a Internet tal cual.

## Comandos de validación

```bash
flutter analyze
flutter test
cd backend && npm test
```

Documentación de referencia: [Apple Wallet Passes](https://developer.apple.com/documentation/walletpasses), [PassKit](https://developer.apple.com/documentation/passkit), [Google Wallet Loyalty Cards](https://developers.google.com/wallet/retail/loyalty-cards), [Flutter en iOS](https://docs.flutter.dev/platform-integration/ios/setup).
