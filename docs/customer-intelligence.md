# Customer Intelligence Engine

Fideli calcula inteligencia comercial por `business_id + customer_id`. Los
datos de dos negocios nunca se combinan y las tablas analíticas solo permiten
lectura a miembros autenticados del negocio correspondiente.

## Qué incluye la fase 1

- Eventos estructurados: visita, compra, sello, puntos, canje, referido, QR,
  Wallet y ajustes.
- Recencia, frecuencia, gasto, ticket promedio y ventanas de 7/30/60/90 días.
- Cadencia personal combinada con la mediana real del negocio cuando el cliente
  todavía tiene poco historial.
- Próxima visita esperada, retraso relativo, tendencias, riesgo y valor.
- Estados visibles simplificados: Nuevo, Preocupante y Riesgo. Los clientes
  dentro de su ritmo habitual no reciben una alerta.
- El motor conserva sus estados y puntajes detallados para estimar la cadencia
  individual; la interfaz agrupa esos resultados en las tres etiquetas visibles.
- Historial de cambios de segmento con razones y una copia de los puntajes.
- Audiencias dinámicas en campañas. La audiencia se resuelve al momento de
  enviar; no se guarda una lista que pueda quedar obsoleta.
- Realtime en Flutter para que los filtros se actualicen sin recargar.

No se usa IA generativa ni un modelo opaco. Cada clasificación es determinista
y conserva `reason_codes` y una explicación corta. Esto permite validar el
resultado con datos reales antes de introducir modelos probabilísticos.

## Despliegue

1. Aplicar las migraciones de Supabase, incluida
   `202610030003_customer_intelligence_phase1.sql`.
2. Desplegar nuevamente la función `wallet` para habilitar campañas por
   segmento y eventos de referidos estructurados.
3. Confirmar en Supabase Cron que existan:
   - `fideli-customer-intelligence-queue` cada minuto.
   - `fideli-customer-intelligence-daily` una vez al día.
4. La migración encola automáticamente a los clientes existentes. También se
   puede ejecutar una reconstrucción manual por negocio:

```sql
select public.refresh_customer_intelligence('<business-uuid>', null);
```

## Cómo se calcula

La cadencia esperada mezcla la mediana personal y la mediana del negocio. El
peso personal crece a medida que hay más visitas y se limita al 85%, por lo que
el sistema evita conclusiones extremas con poco historial.

El riesgo combina retraso respecto a la cadencia, caída de frecuencia y
tendencia reciente. El valor combina frecuencia relativa y gasto relativo del
negocio. Los estados visibles agrupan el resultado: Nuevo para clientes con
poco historial, Preocupante para clientes que empiezan a retrasarse y Riesgo
para quienes superaron ampliamente su cadencia esperada. Frecuentes, regulares,
ocasionales y recuperados siguen siendo señales internas del motor, no filtros
principales para el comercio.

## Próximas fases

Cuando exista suficiente historial estable se pueden añadir cohortes y RFM más
avanzado, automatizaciones, BG/NBD, Gamma-Gamma y CLV. Esos modelos no deben
activarse antes de medir cobertura, consistencia y calidad de los eventos de la
fase 1.
