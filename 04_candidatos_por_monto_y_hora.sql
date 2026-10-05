-- =============================================================================
-- 04 · Candidatos por monto y hora del banco (búsqueda rápida)
-- -----------------------------------------------------------------------------
-- Versión liviana para el caso típico: tienes una fila de la cartola (monto y
-- hora) que la app marca "sin contraparte en Vita" y quieres ver qué
-- transacciones de Vita podrían ser, de CUALQUIER proveedor y estado.
--
-- Devuelve pocas columnas, sin datos personales, ordenadas por cercanía en
-- tiempo. Si encuentras el candidato, copia su ID de transacción y búscalo
-- con el archivo 02 para ver el detalle completo.
--
-- Qué editar:
--   zona               zona horaria del banco
--   hora_banco_local   hora del movimiento en la cartola (hora local)
--   minutos_antes      cuánto antes de esa hora buscar en Vita
--   minutos_despues    cuánto después
--   monto              monto de la cartola
--   tolerancia         diferencia permitida (unidades de la moneda)
--
-- Ventanas sugeridas (ver README):
--   Depósitos/abonos:            Vita registra 0 a 10 min después del banco
--                                -> minutos_antes 15, minutos_despues 30
--   Envíos (Coopcentral, BCI):   el banco debita hasta ~15 h después de crear el envío
--                                -> minutos_antes 900, minutos_despues 10
--   Corte del día / fin de semana: amplía a 3 días (4320 min) hacia atrás
-- =============================================================================

WITH parametros AS (
    SELECT
        'America/Bogota'                  AS zona,
        TIMESTAMP '2026-09-29 17:33:15'   AS hora_banco_local,
        60                                AS minutos_antes,
        60                                AS minutos_despues,
        CAST(340036 AS numeric)           AS monto,
        CAST(100 AS numeric)              AS tolerancia
),
rango AS (
    SELECT
        p.*,
        (p.hora_banco_local AT TIME ZONE p.zona) AT TIME ZONE 'UTC' AS hora_banco_utc
    FROM parametros p
)
SELECT
    t.id                                                        AS ID_de_transaccion,
    t.alt_id                                                    AS ID_publico,
    t.created_at                                                AS Fecha_UTC,
    (t.created_at AT TIME ZONE 'UTC') AT TIME ZONE r.zona       AS Fecha_local,
    ROUND(EXTRACT(EPOCH FROM (t.created_at - r.hora_banco_utc)) / 60, 1)
                                                                AS Minutos_vs_banco,
    CASE t.category::int
        WHEN 0 THEN 'Sent'        WHEN 1 THEN 'Received'   WHEN 2 THEN 'Deposit'
        WHEN 3 THEN 'Withdrawal'  WHEN 4 THEN 'Exchange'   WHEN 5 THEN 'Fee'
        WHEN 6 THEN 'Payment'     WHEN 7 THEN 'Transfer'   WHEN 12 THEN 'Adjustment'
        ELSE t.category::text
    END                                                         AS Tipo,
    CASE t.status::int
        WHEN 0 THEN 'Started'   WHEN 1 THEN 'Completed' WHEN 2 THEN 'Pending'
        WHEN 3 THEN 'Denied'    WHEN 4 THEN 'Processed' WHEN 5 THEN 'Failed'
        WHEN 6 THEN 'Time Out'  WHEN 7 THEN 'Checking'
    END                                                         AS Estado,
    t.external_provider                                         AS Proveedor_num,
    UPPER(t.currency_iso_code)                                  AS Moneda,
    ROUND(t.amount::numeric, 2)                                 AS Monto,
    ROUND(t.total::numeric, 2)                                  AS Total,
    ROUND(t.amount_local_currency::numeric, 2)                  AS Total_en_destino,
    LEAST(ABS(t.amount::numeric - r.monto),
          ABS(t.total::numeric - r.monto),
          ABS(COALESCE(t.amount_local_currency::numeric, t.amount::numeric) - r.monto))
                                                                AS Diferencia_de_monto,
    t.external_id                                               AS ID_externo,
    LEFT(t.description, 60)                                     AS Descripcion,
    t.deleted_at
FROM transactions t
CROSS JOIN rango r
WHERE t.created_at BETWEEN r.hora_banco_utc - (r.minutos_antes   || ' minutes')::interval
                       AND r.hora_banco_utc + (r.minutos_despues || ' minutes')::interval
  AND (   ABS(t.amount::numeric - r.monto) <= r.tolerancia
       OR ABS(t.total::numeric  - r.monto) <= r.tolerancia
       OR (t.amount_local_currency IS NOT NULL
           AND ABS(t.amount_local_currency::numeric - r.monto) <= r.tolerancia))
ORDER BY ABS(EXTRACT(EPOCH FROM (t.created_at - r.hora_banco_utc))), Diferencia_de_monto
LIMIT 50
;

-- Proveedor_num: 5 Fintoc, 6 Transbank, 11 Bancolombia, 13 Bind (PSAV), 21 BCI,
--                28 Rendimento, 30 Bitso, 36 Coopcentral, 37 Bind PSP, 38 Breb,
--                40 Redenlace, 41 Bithonor (lista completa en el archivo 01).
