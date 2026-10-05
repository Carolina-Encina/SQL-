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
| Santander 977, Fintoc, Transbank, BCI (Chile) | `America/Santiago` (UTC‑3 en verano, UTC‑4 en invierno) |
| Bancolombia, Coopcentral / Breb (Colombia) | `America/Bogota` (UTC‑5) |
| BIND, BIND PSP, QR (Coelsa), CVU DINAMICO (Argentina) | `America/Argentina/Buenos_Aires` (UTC‑3) |

Si en tu base `created_at` fuera `timestamptz` (con zona) en vez de `timestamp`, cambia `(t.created_at AT TIME ZONE 'UTC') AT TIME ZONE r.zona` por `t.created_at AT TIME ZONE r.zona`.

## Ventanas de búsqueda por banco

| Banco | Qué cuadrar | Rango en hora local |
|---|---|---|
| Cualquiera | Día calendario D | De D 00:00 a D+1 00:00 |
| BCI | Fecha contable D | De las 14:00 del día hábil anterior a las 14:00 de D |
| BCI | Nómina de las 02:00 | Envíos creados desde las ~22:50 del día anterior |
| Santander 977 | Abono del día D | De las 14:00 del día hábil anterior a las 14:00 de D |
| BIND PSP | Día de banco D | De las 22:50 de D‑1 a las 22:50 de D |
| Bancolombia | Envíos ACH | Corte ~15:00 Colombia; Bancolombia y Nequi ~20:00 a 22:00 |
| Cualquiera | Lunes | Desde el corte del viernes (incluye el fin de semana) |

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
