# Consultas SQL para conciliación (BBDD Vita)

Consultas para cruzar la BBDD de Vita con las cartolas de los bancos y con la app de conciliaciones. Están escritas para PostgreSQL y usan las mismas tablas que la consulta base del equipo.

| Archivo | Para qué sirve |
|---|---|
| `01_consulta_base_por_proveedor.sql` | Todas las transacciones de un proveedor en un rango, con el día en hora local del banco. |
| `02_buscar_por_id.sql` | Buscar uno o varios IDs: de transacción, público, externo (con o sin `admn_`/`usr_`) o UUID de orden de pago. |
| `03_buscar_por_caracteristicas.sql` | Buscar cuando "no es Vita": monto con tolerancia, RUT/DNI/CUIT, nombre, email, usuario, cuenta, parte del ID externo o de la descripción. |
| `04_candidatos_por_monto_y_hora.sql` | Búsqueda rápida y sin datos personales: candidatos de cualquier proveedor para una fila de la cartola (monto + hora). |

En todos los archivos solo se edita el bloque `parametros` del inicio.

## Cómo se usa en un caso "no es Vita"

1. **Tienes un ID** (de la app, la cartola o el reporte del proveedor): corre el **02**. La columna `Coincide_por` dice si calzó por ID de transacción, ID público, ID externo o descripción.
2. **No aparece, o solo tienes monto y hora:** corre el **04** con la hora y el monto de la cartola. Busca en todos los proveedores y estados.
3. **Sigue sin aparecer:** corre el **03** con lo que sepas (RUT del remitente, nombre, cuenta, parte del ID externo) y amplía la tolerancia o el rango.
4. Cuando tengas el ID de transacción, vuelve al **02** para ver el detalle y sus filas hermanas.

## Zona horaria

La BBDD guarda `created_at` en **UTC**. Las consultas convierten el rango que escribes en hora local del banco a UTC, y agregan la columna `Fecha_local`. Así no hay que sumar ni restar horas a mano.

| Banco o proveedor | `zona` |
|---|---|
| Chile: Santander 977/738/374/USD, Fintoc, Transbank, BCI Chile y USD, Los Héroes | `America/Santiago` (UTC‑3 en verano, UTC‑4 en invierno) |
| Colombia: Bancolombia 193/198, Coopcentral / Breb, Wompi, Pomelo Colombia | `America/Bogota` (UTC‑5) |
| Argentina: BIND PSAV, BIND PSP, QR (Coelsa), CVU DINAMICO, Pomelo Argentina | `America/Argentina/Buenos_Aires` (UTC‑3) |
| Perú: B89, Alfín | `America/Lima` (UTC‑5) |
| Bolivia: Ecofuturo | `America/La_Paz` (UTC‑4) |
| Brasil: Rendimento | `America/Sao_Paulo` (UTC‑3) |
| Venezuela: TransferSwap | `America/Caracas` (UTC‑4) |
| Binance y Binance Argentina (exportan en UTC‑5) | `America/Bogota` |
| DLocal, NIUM, BVNK, Bitso, Circle, Bridge, Bridge DFNS | `UTC` |
| BCI Miami, Mercury | `America/New_York` |

Si en tu base `created_at` fuera `timestamptz` (con zona) en vez de `timestamp`, cambia `(t.created_at AT TIME ZONE 'UTC') AT TIME ZONE r.zona` por `t.created_at AT TIME ZONE r.zona`.

## Horarios y ventanas de búsqueda por banco

Todos los bancos de la app de conciliaciones. "Ventana" es el rango que hay que poner en `desde_local` / `hasta_local` (archivos 01 y 03) para que la BBDD calce con un día de la cartola. Si no se indica otra cosa, el día va de D 00:00 a D+1 00:00 en la `zona` indicada.

Fuente: **V** = verificado con cartolas reales (sep‑2026); **N** = página "Proceso Conciliaciones" de Notion (02/10/2026); **—** = sin dato todavía.

### Chile · `America/Santiago` (UTC‑3 de septiembre a abril, UTC‑4 de abril a septiembre)

| Banco en la app | Proveedor BBDD | Horario / corte | Ventana BBDD para el día D | Fuente |
|---|---|---|---|---|
| Santander 977 | 5 Fintoc | Corte del día de banco a las **14:00**; el lunes trae desde el viernes 14:00. Notion indica 18:00 | De D‑1 (hábil) 14:00 a D 14:00 | V / N |
| Fintoc | 5 Fintoc | La app agrupa por Transaction Date en hora Chile. Pagos sin Transaction Date (Banco Ripley) quedan fuera | Día calendario | V |
| Santander 738 | 6 Transbank | Recibe el abono de Transbank por "Fecha de abono" | Ventas de los días que componen el abono | V / N |
| Transbank | 6 Transbank | Débito y prepago: venta antes de 14:00 → abono T+1, después → T+2. Crédito: T+2 a T+3 hábiles | Día calendario por fecha de venta | V |
| BCI Chile | 21 BCI | App = Fecha transacción. Corte contable **14:00**. Nómina cada 5 min de 02:00 a ~22:50 | Día calendario; por fecha contable de D‑1 (hábil) 14:00 a D 14:00 | V |
| BCI Chile USD | — (tesorería) | Neto diario ≈ 0; no cruza contra Vita | Día calendario | N |
| Santander 374 | — (traslados) | Cuenta administrativa; traslados internos a mano | Día calendario | N |
| Santander USD | Recargas manuales | Corte diario por fecha | Día calendario | — |
| Los Héroes | 12 Floyd Heroes | Recargas manuales; insumo mensual de Finanzas (hoja PLH) | Mes | — |

### Colombia · `America/Bogota` (UTC‑5, sin horario de verano)

| Banco en la app | Proveedor BBDD | Horario / corte | Ventana BBDD para el día D | Fuente |
|---|---|---|---|---|
| Bancolombia 193 / 198 | 11 Bancolombia | Pagos cuenta 7160: último del día entre 20:30 y 21:30. Cuenta 9729: 22:00 a 23:00. ACH a otros bancos: corte ~15:00 (pasa al día hábil siguiente). Desde las 15:00 hay zona gris; desde las 22:00 siempre D+1. Fin de semana: ~40 % de la tarde pasa al día siguiente | De D‑1 21:00 a D 21:00 (si no está, buscar en D+1) | V / N |
| Coopcentral (Breb) | 38 Breb | Payins calzan al segundo con el banco. Envíos se debitan de 4 min a 15 h después de crearse (lo de la noche sale ~08:17) | Día calendario; para envíos, hasta 15 h antes | V |
| Wompi | 15 Wompi | BBDD = Wompi + 5 h. La cartola no es diaria: agrupa varios días bajo la fecha de pago del lote | Día calendario; buscar el lote en D+1 o D+2 | N |
| Pomelo Colombia | 26 Pomelo | Desfase variable de 0 a 7 h; transacciones "held" hasta 7 días después | Día calendario ± 7 días | N |

### Argentina · `America/Argentina/Buenos_Aires` (UTC‑3, sin horario de verano)

| Banco en la app | Proveedor BBDD | Horario / corte | Ventana BBDD para el día D | Fuente |
|---|---|---|---|---|
| BIND PSAV | 13 Bind | Bind = BBDD − 3 h | Día calendario | V / N |
| QR (Coelsa) | 13 Bind (`vita-bind-…`) | Bind = BBDD − 3 h; filtrar estado Acreditados | Día calendario | V / N |
| CVU DINAMICO | 13 Bind (`vita-bind-psp-…`, `vita-bind-boton-…`) | CVU = BBDD − 3 h | Día calendario | V / N |
| BIND PSP | 37 Bind PSP | Corte del día de banco a las **~22:50**; el lunes incluye el fin de semana | De D‑1 22:50 a D 22:50 (lunes: desde el viernes 22:50) | V |
| Pomelo Argentina | 26 Pomelo | Desfase de 0 a 7 h; "held" hasta 7 días | Día calendario ± 7 días | N |
| Binance Argentina | — (tesorería) | Igual que Binance: exporta en UTC‑5 | Usar `zona = 'America/Bogota'` (UTC‑5) | N |

### Perú, Bolivia, Brasil, Venezuela

| Banco en la app | `zona` | Proveedor BBDD | Horario / corte | Ventana BBDD para el día D | Fuente |
|---|---|---|---|---|---|
| B89 (PEN + USD) | `America/Lima` (UTC‑5) | 31 B89 | B89 = BBDD − 5 h. Lo creado en B89 entre 19:00 y 23:59 aparece en BBDD al día siguiente | Día calendario; si falta, D‑1 y D+1 | N |
| Alfín USD / Soles | `America/Lima` (UTC‑5) | 25 Alfin | Recargas manuales; ITF y comisiones por regla | Día calendario | — |
| Ecofuturo | `America/La_Paz` (UTC‑4) | 40 Redenlace | Comisión Bs 10 por ACH; matcher no concilia (manual) | Día calendario | N |
| Rendimento | `America/Sao_Paulo` (UTC‑3) | 28 Rendimento | Cartola sin hora; la cartola del día D trae lo de D‑1 | D‑1 completo | N |
| TransferSwap | `America/Caracas` (UTC‑4) | 29 TransferSwap | — | Día calendario | — |

### Proveedores globales, cripto y tesorería

| Banco en la app | `zona` | Proveedor BBDD | Horario / corte | Ventana BBDD para el día D | Fuente |
|---|---|---|---|---|---|
| DLocal Payouts | `UTC` | 0 dLocal | Mismo huso que la BBDD; sin corte | Día calendario UTC | N |
| DLocal Fondeos | `UTC` | — (tesorería) | Se valida contra el wire de BCI Miami | Día calendario | N |
| NIUM | `UTC` | 17 Nium | Sin huso fijo; Solo Vita entre 19:00 y 23:59 UTC entran en la cartola de D+1 | Día calendario; pagos grandes faltantes en D+1 | N |
| BVNK | `UTC` | 39 BVNK | Lo de 00:00 a ~03:00 queda en el día siguiente | Día calendario; revisar D‑1 y D+1 | N |
| Bitso | `UTC` | 30 Bitso | Cartola = admin, sin desfase | Día calendario UTC | N |
| Binance | `America/Bogota` (UTC‑5) | 8 Binance / 14 Binance Pay | La cartola se exporta en UTC‑5; cruza por hash | Día calendario en UTC‑5 | N |
| Circle | `UTC` | 9 Circle | Circle ~5 h después de Binance; BBDD ~4 h después de Binance | Día calendario ± 5 h | N |
| Bridge | `UTC` | 27 Bridge | On‑ramp USDC; cruza contra Binance por hash | Día calendario UTC | — |
| Bridge DFNS | `UTC` | 20 DFNS | Hot wallets on‑chain | Día calendario UTC | — |
| BCI Miami | `America/New_York` | — (tesorería) | Cuenta de tránsito a proveedores; no cruza contra Vita | Día calendario | N |
| Mercury | `America/New_York` | Recargas manuales | Corte diario por fecha | Día calendario | — |

### Reglas que aplican a todos

| Caso | Qué hacer |
|---|---|
| Lunes | Empezar desde el corte del viernes: incluye el fin de semana |
| Último día subido | Lo de Vita posterior a la hora de descarga de la cartola queda "Solo en Vita" hasta subir la cartola completa |
| Consulta que termina a las 23:59 UTC | Pierde las últimas horas del día local: 3 h en Chile y Argentina, 4 h en Bolivia y Venezuela, 5 h en Colombia y Perú |

## Qué monto comparar

| Caso | Columna de la BBDD |
|---|---|
| Depósitos con comisión (Fintoc, Transbank) | `Total` |
| Envíos con costo fijo o desde otra moneda (Coopcentral, BCI, BIND) | `Total_en_destino` |
| Payins de enlace (Breb) | `Monto`, con diferencias de 1 a 90 COP o centavos |

Los archivos 03 y 04 comparan contra `Monto`, `Total` y `Total_en_destino` a la vez, y la columna `Coincide_por` dice cuál calzó.

## IDs útiles por proveedor

| Proveedor | Dónde está el ID en la cartola o reporte | Cómo aparece en la BBDD (`ID_Externo`) |
|---|---|---|
| Fintoc | Fintoc Payment Id | `admn_pi_…` / `usr_pi_…` (a veces `fintoc-cs_…`) |
| BIND PSP | Referencia (22 caracteres) | igual a la referencia |
| Bind (PSAV) | Referencia / recarga | `NSBT-1-…-759667-…`, envíos `1-30717447243-…` |
| Bind PSP (envíos) | — | `1-30717474895-…` |
| Bancolombia | ID Externo del admin | `COBCaaaammddhhmm-<id>` |
| Transbank | — | `admn_<hash>` / `usr_<hash>` |
| Breb | — | `admn_…` / `usr_…`; huérfanos `admn_orphan-…` |

## Buenas prácticas

- Los resultados traen datos personales (nombres, documentos, correos). No subas resultados ni exportaciones al repositorio, solo las consultas.
- Usa siempre un rango de fechas acotado en el 03: las búsquedas por texto (`ILIKE`) recorren todas las filas del rango.
- Un enlace de pago genera dos filas ("Incoming transaction" y "Deposit transaction to user"). Solo la primera va contra el banco.
