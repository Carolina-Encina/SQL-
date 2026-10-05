-- =============================================================================
-- 03 · Buscar por características
-- -----------------------------------------------------------------------------
-- Para cuando la app o la cartola dicen "no está en Vita" pero el movimiento
-- sí existe con otro dato: otro monto (comisión, centavos, moneda de origen),
-- otra hora (corte del banco, UTC), otro proveedor u otro estado (Denied).
--
-- Cómo usarlo: completa SOLO los criterios que conoces y deja el resto en NULL.
-- Los criterios que completes se combinan con Y (deben cumplirse todos).
-- El rango de fechas es obligatorio para no recorrer toda la tabla.
-- La columna "Coincide_por" dice qué campo calzó y "Diferencia_de_monto"
-- cuánto difiere del monto buscado (los resultados salen ordenados por eso).
--
-- Criterios:
--   desde_local / hasta_local  rango en hora local del banco (obligatorio)
--   zona                       zona horaria del banco (ver archivo 01)
--   monto                      monto que ves en la cartola o la app
--   tolerancia_monto           diferencia permitida en unidades (ej.: 100 COP, 1 CLP)
--   tolerancia_pct             diferencia permitida en % (ej.: 2 = 2 %); se usa la mayor
--                              El monto se compara contra Monto, Total y Total_en_destino:
--                              el banco a veces debita Total_en_destino (envíos sin costo
--                              fijo o desde otra moneda) o abona el Total (con comisión).
--   documento                  RUT, DNI o CUIT, con o sin puntos/guion (emisor, receptor,
--                              CUIT secundario o beneficiario)
--   nombre                     parte del nombre (emisor, receptor o beneficiario)
--   email                      parte del correo (emisor o receptor)
--   usuario_id                 ID de usuario Vita (como emisor o receptor)
--   texto_id_externo           parte del ID externo (ej.: NSBT-1-1-759667, 30717474895)
--   texto_descripcion          parte de la descripción (ej.: UUID de orden de pago)
--   cuenta_bancaria            parte del número de cuenta del beneficiario
--   proveedor                  número de external_provider (NULL = todos)
--   categoria                  número de category: 2 Deposit, 3 Withdrawal, 6 Payment,
--                              7 Transfer, 0 Sent... (NULL = todas)
--   solo_completadas           TRUE = solo Completed; FALSE = todos los estados
-- =============================================================================

WITH parametros AS (
    SELECT
        'America/Santiago'                  AS zona,
        TIMESTAMP '2026-09-28 00:00:00'     AS desde_local,
        TIMESTAMP '2026-10-02 00:00:00'     AS hasta_local,      -- exclusivo
        CAST(91981 AS numeric)              AS monto,            -- NULL si no aplica
        CAST(1 AS numeric)                  AS tolerancia_monto,
        CAST(0 AS numeric)                  AS tolerancia_pct,
        CAST(NULL AS text)                  AS documento,        -- ej.: '16.156.118-5'
        CAST(NULL AS text)                  AS nombre,           -- ej.: 'perez'
        CAST(NULL AS text)                  AS email,
        CAST(NULL AS bigint)                AS usuario_id,
        CAST(NULL AS text)                  AS texto_id_externo,
        CAST(NULL AS text)                  AS texto_descripcion,
        CAST(NULL AS text)                  AS cuenta_bancaria,
        CAST(NULL AS int)                   AS proveedor,
        CAST(NULL AS int)                   AS categoria,
        FALSE                               AS solo_completadas
),
rango AS (
    SELECT
        p.*,
        (p.desde_local AT TIME ZONE p.zona) AT TIME ZONE 'UTC' AS desde_utc,
        (p.hasta_local AT TIME ZONE p.zona) AT TIME ZONE 'UTC' AS hasta_utc,
        LOWER(REGEXP_REPLACE(COALESCE(p.documento, ''), '[^0-9kK]', '', 'g')) AS doc_limpio,
        GREATEST(COALESCE(p.tolerancia_monto, 0),
                 COALESCE(p.monto, 0) * COALESCE(p.tolerancia_pct, 0) / 100) AS tolerancia
    FROM parametros p
),
coincidencias AS (
    SELECT
        t.id,
        CONCAT_WS(' | ',
            CASE WHEN r.monto IS NOT NULL AND ABS(t.amount::numeric - r.monto) <= r.tolerancia
                 THEN 'Monto ' || ROUND(t.amount::numeric, 2) END,
            CASE WHEN r.monto IS NOT NULL AND ABS(t.total::numeric - r.monto) <= r.tolerancia
                 THEN 'Total ' || ROUND(t.total::numeric, 2) END,
            CASE WHEN r.monto IS NOT NULL AND t.amount_local_currency IS NOT NULL
                      AND ABS(t.amount_local_currency::numeric - r.monto) <= r.tolerancia
                 THEN 'Total en destino ' || ROUND(t.amount_local_currency::numeric, 2) END,
            CASE WHEN r.doc_limpio <> '' THEN 'Documento' END,
            CASE WHEN r.nombre IS NOT NULL THEN 'Nombre' END,
            CASE WHEN r.email IS NOT NULL THEN 'Email' END,
            CASE WHEN r.usuario_id IS NOT NULL THEN 'Usuario' END,
            CASE WHEN r.texto_id_externo IS NOT NULL THEN 'ID externo' END,
            CASE WHEN r.texto_descripcion IS NOT NULL THEN 'Descripción' END,
            CASE WHEN r.cuenta_bancaria IS NOT NULL THEN 'Cuenta bancaria' END
        ) AS coincide_por,
        CASE WHEN r.monto IS NOT NULL THEN LEAST(
            ABS(t.amount::numeric - r.monto),
            ABS(t.total::numeric - r.monto),
            ABS(COALESCE(t.amount_local_currency::numeric, t.amount::numeric) - r.monto)
        ) END AS diferencia_monto
    FROM transactions t
    CROSS JOIN rango r
    LEFT JOIN users u_s        ON u_s.id = t.sender_id
    LEFT JOIN users u_r        ON u_r.id = t.recipient_id
    LEFT JOIN beneficiaries be ON be.id = t.beneficiary_id
    WHERE t.created_at >= r.desde_utc
      AND t.created_at <  r.hasta_utc
      AND (r.proveedor IS NULL OR t.external_provider = r.proveedor)
      AND (r.categoria IS NULL OR t.category = r.categoria)
      AND (NOT r.solo_completadas OR t.status = 1)
      AND (r.monto IS NULL
           OR ABS(t.amount::numeric - r.monto) <= r.tolerancia
           OR ABS(t.total::numeric  - r.monto) <= r.tolerancia
           OR (t.amount_local_currency IS NOT NULL
               AND ABS(t.amount_local_currency::numeric - r.monto) <= r.tolerancia))
      AND (r.doc_limpio = ''
           OR LOWER(REGEXP_REPLACE(COALESCE(u_s.document_number, ''), '[^0-9kK]', '', 'g')) = r.doc_limpio
           OR LOWER(REGEXP_REPLACE(COALESCE(u_r.document_number, ''), '[^0-9kK]', '', 'g')) = r.doc_limpio
           OR LOWER(REGEXP_REPLACE(COALESCE(u_s.secondary_document_number, ''), '[^0-9kK]', '', 'g')) = r.doc_limpio
           OR LOWER(REGEXP_REPLACE(COALESCE(u_r.secondary_document_number, ''), '[^0-9kK]', '', 'g')) = r.doc_limpio
           OR LOWER(REGEXP_REPLACE(COALESCE(be.document_number, ''), '[^0-9kK]', '', 'g')) = r.doc_limpio)
      AND (r.nombre IS NULL
           OR CONCAT(u_s.first_name, ' ', u_s.last_name) ILIKE '%' || r.nombre || '%'
           OR CONCAT(u_r.first_name, ' ', u_r.last_name) ILIKE '%' || r.nombre || '%'
           OR CONCAT(be.first_name, ' ', be.last_name, ' ', be.company_name) ILIKE '%' || r.nombre || '%')
      AND (r.email IS NULL
           OR u_s.email ILIKE '%' || r.email || '%'
           OR u_r.email ILIKE '%' || r.email || '%')
      AND (r.usuario_id IS NULL OR t.sender_id = r.usuario_id OR t.recipient_id = r.usuario_id)
      AND (r.texto_id_externo IS NULL OR t.external_id ILIKE '%' || r.texto_id_externo || '%')
      AND (r.texto_descripcion IS NULL OR t.description ILIKE '%' || r.texto_descripcion || '%')
      AND (r.cuenta_bancaria IS NULL OR t.account_bank->>'account_bank' ILIKE '%' || r.cuenta_bancaria || '%')
)
SELECT DISTINCT
    c.coincide_por AS Coincide_por,
    c.diferencia_monto AS Diferencia_de_monto,
    t.id AS ID_de_transaccion,
    t.alt_id AS ID_publico,
    u_sender.id AS Emisor_ID,
    CONCAT(u_sender.first_name, ' ', u_sender.last_name) AS Emisor_Nombres_y_Apellidos,
    CASE u_sender.document_type::int
        WHEN 0 THEN 'DNI'
        WHEN 1 THEN 'Company ID'
        WHEN 2 THEN 'Passport'
        WHEN 3 THEN 'DNI Foreigner'
        WHEN 4 THEN 'Company RUC'
        WHEN 5 THEN 'Special Type'
    END AS Emisor_Tipo_de_documento,
    u_sender.document_number AS Emisor_Numero_de_documento,
    u_sender.secondary_document_number AS CUIT_Numero_Emisor,
    u_sender.email AS Emisor_Correo_electronico,
    u_sender.address AS Emisor_Direccion,
    u_recipient.id AS Receptor_ID,
    CONCAT(u_recipient.first_name, ' ', u_recipient.last_name) AS Receptor_Nombres_y_Apellidos,
    CASE u_recipient.document_type::int
        WHEN 0 THEN 'DNI'
        WHEN 1 THEN 'Company ID'
        WHEN 2 THEN 'Passport'
        WHEN 3 THEN 'DNI Foreigner'
        WHEN 4 THEN 'Company RUC'
        WHEN 5 THEN 'Special Type'
    END AS Receptor_Tipo_de_documento,
    u_recipient.document_number AS Receptor_Numero_de_documento,
    u_recipient.secondary_document_number AS CUIT_Numero_Receptor,
    u_recipient.email AS Receptor_Correo_electronico,
    u_recipient.address AS Receptor_Direccion,
    t.description AS Descripcion,
    CASE
        WHEN t.currency IN (1, 5) THEN ROUND(t.amount::numeric, 8)
        ELSE ROUND(t.amount::numeric, 2)
    END AS "Monto",
    CASE
        WHEN t.currency IN (1, 5) THEN ROUND(t.total::numeric, 8)
        ELSE ROUND(t.total::numeric, 2)
    END AS "Total",
    t.created_at AS "Fecha",
    (t.created_at AT TIME ZONE 'UTC') AT TIME ZONE r.zona AS "Fecha_local",
    t.deleted_at,
    UPPER(t.currency_iso_code) AS Moneda,
    CASE LOWER(t.default_currency)
        WHEN 'eth' THEN 'ETH'
        WHEN 'btc' THEN 'BTC'
        WHEN 'clp' THEN 'CLP'
        WHEN 'usd' THEN 'USD'
        WHEN 'cop' THEN 'COP'
        WHEN 'usdt' THEN 'USDT'
        WHEN 'usdc' THEN 'USDC'
        WHEN 'ars' THEN 'ARS'
        WHEN 'mxn' THEN 'MXN'
        ELSE NULL
    END AS "Moneda_por_defecto",
    CASE
        WHEN t.category IN (12, 13, 15, 16, 17) THEN NULL
        ELSE t.account_bank->>'bank'
    END AS "Banco",
    CASE
        WHEN t.category IN (12, 13, 15, 16, 17) THEN NULL
        ELSE t.account_bank->>'account_bank'
    END AS "Cuenta_de_banco",
    CASE t.category::int
        WHEN 0 THEN 'Sent'
        WHEN 1 THEN 'Received'
        WHEN 2 THEN 'Deposit'
        WHEN 3 THEN 'Withdrawal'
        WHEN 4 THEN 'Exchange'
        WHEN 5 THEN 'Fee'
        WHEN 6 THEN 'Payment'
        WHEN 7 THEN 'Transfer'
        WHEN 8 THEN 'Vita Card'
        WHEN 9 THEN 'Tax'
        WHEN 10 THEN 'Cash Back Coupon'
        WHEN 11 THEN 'Service Payment'
        WHEN 12 THEN 'Adjustment'
        WHEN 13 THEN 'Card Credit Adjustment'
        WHEN 14 THEN 'Card Debit Adjustment'
        WHEN 15 THEN 'Card Transaction'
        WHEN 16 THEN 'Request Charge'
        WHEN 17 THEN 'Card Maintenance'
    END AS "Tipo_de_transaccion",
    CASE
        WHEN t.category = 4
             AND LOWER(t.currency_iso_code) IN ('btc', 'usdt', 'usdc')
             AND u_recipient.id = 1
             AND u_sender.id NOT IN (179851,113052,1,21233,21234,21235,21232,37345,33529,57653,56026,136915,30043,96706,98319,2201)
             THEN 'Venta Cripto'
        WHEN t.category = 4
             AND LOWER(t.currency_iso_code) NOT IN ('btc', 'usdt', 'usdc')
             AND u_recipient.id = 1
             AND u_sender.id NOT IN (179851,113052,1,21233,21234,21235,21232,37345,33529,57653,56026,136915,30043,96706,98319,2201)
             THEN 'Compra Cripto'
        ELSE NULL
    END AS Exchange_Cripto_User,
    CASE
        WHEN t.category = 4
             AND LOWER(t.currency_iso_code) IN ('btc', 'usdt', 'usdc')
             AND u_recipient.id = 1
             THEN 'Venta Cripto'
        WHEN t.category = 4
             AND LOWER(t.currency_iso_code) IN ('btc', 'usdt', 'usdc')
             AND u_sender.id = 1
             THEN 'Compra Cripto'
        ELSE NULL
    END AS Seba_Cripto,
    CASE t.status::int
        WHEN 0 THEN 'Started'
        WHEN 1 THEN 'Completed'
        WHEN 2 THEN 'Pending'
        WHEN 3 THEN 'Denied'
        WHEN 4 THEN 'Processed'
        WHEN 5 THEN 'Failed'
        WHEN 6 THEN 'Time Out'
        WHEN 7 THEN 'Checking'
    END AS Estado_de_transaccion,
    CASE
        WHEN t.country_iso_code IS NOT NULL THEN (SELECT name FROM countries WHERE iso_code = t.country_iso_code)
        WHEN u_recipient.country_id IS NOT NULL THEN (SELECT name FROM countries WHERE id = u_recipient.country_id)
        ELSE NULL
    END AS Pais_destino,
    CASE t.source::int
        WHEN 0 THEN 'Web'
        WHEN 1 THEN 'iOS'
        WHEN 2 THEN 'Android'
        WHEN 3 THEN 'Blockchain'
        WHEN 4 THEN 'Console'
        WHEN 5 THEN 'Admin'
        WHEN 6 THEN 'Business'
        WHEN 7 THEN 'Banking Network'
        WHEN 8 THEN 'Batch'
        WHEN 9 THEN 'Card'
        WHEN 10 THEN 'Card Adjustment'
    END AS "Fuente",
    t.hash_result AS Resultado_hash,
    t.currency_to_default_currency_price AS Tasa_de_cambio,
    t.amount_local_currency AS Total_en_destino,
    CASE t.external_provider::int
        WHEN 0 THEN 'dLocal'
        WHEN 1 THEN 'Wyre'
        WHEN 2 THEN 'Ripple'
        WHEN 3 THEN 'Manual'
        WHEN 4 THEN 'Powwi'
        WHEN 5 THEN 'Fintoc'
        WHEN 6 THEN 'Transbank'
        WHEN 7 THEN 'Floyd'
        WHEN 8 THEN 'Binance'
        WHEN 9 THEN 'Circle'
        WHEN 10 THEN 'Reserve'
        WHEN 11 THEN 'Bancolombia'
        WHEN 12 THEN 'Floyd Heroes'
        WHEN 13 THEN 'Bind'
        WHEN 14 THEN 'Binance Pay'
        WHEN 15 THEN 'Wompi'
        WHEN 16 THEN 'Fortress'
        WHEN 17 THEN 'Nium'
        WHEN 18 THEN 'STP'
        WHEN 19 THEN 'Sandya'
        WHEN 20 THEN 'DFNS'
        WHEN 21 THEN 'BCI'
        WHEN 22 THEN 'Khipu'
        WHEN 23 THEN 'Pagacel'
        WHEN 24 THEN 'Skrill'
        WHEN 25 THEN 'Alfin'
        WHEN 26 THEN 'Pomelo'
        WHEN 27 THEN 'Bridge'
        WHEN 28 THEN 'Rendimento'
        WHEN 29 THEN 'TransferSwap'
        WHEN 30 THEN 'Bitso'
        WHEN 31 THEN 'B89'
        WHEN 32 THEN 'Occidente'
        WHEN 33 THEN 'CBPay'
        WHEN 34 THEN 'Sandya_API'
        WHEN 35 THEN 'Checkbook'
        WHEN 36 THEN 'Coopcentral'
        WHEN 37 THEN 'Bind PSP'
        WHEN 38 THEN 'Breb'
        WHEN 39 THEN 'BVNK'
        WHEN 40 THEN 'Redenlace'
        WHEN 41 THEN 'Bithonor'
    END AS Proveedor_Externo,
    t.external_id AS ID_Externo,
    b.document_type AS Tipo_de_documento_destinatario,
    REPLACE(REPLACE(b.document_number, ' ', ''), '.', '') AS Numero_de_documento_del_beneficiario,
    CASE
        WHEN LOWER(b.beneficiary_type) = 'corporate' THEN b.company_name
        ELSE CONCAT(b.first_name, ' ', b.last_name)
    END AS Nombre_y_apellido_del_beneficiario,
    t.spot_price AS Tasa_spot,
    t.currency_to_default_currency_price AS Tasa_spread,
    t.fixed_cost AS Costo_fijo,
    t.local_currency AS Moneda_destino,
    t.spot_origin_usd AS Precio_Spot_Origen_USD,
    t.spot_usd_destiny AS Precio_Spot_Destino_USD,
    t.total_fee,
    t.is_processed_automatically AS Procesado_automaticamente,
    CASE u_sender.category::int
        WHEN 0 THEN 'Natural'
        WHEN 1 THEN 'Business'
    END AS Categoria_del_Emisor,
    b.id AS Beneficiary_User_id,
    CASE
        WHEN b.beneficiary_type ILIKE 'corporate' THEN 'Empresa'
        WHEN b.beneficiary_type ILIKE 'individual' THEN 'Individual'
        ELSE 'Otro'
    END AS Tipo_de_Usuario_Beneficiario,
    u_beneficiary.secondary_document_number AS CUIT_Beneficiario,
    u_sender.accept_pep AS is_pep,
    t.usd_amount AS Monto_en_USD,
    t.to_address,
    country.name AS Pais_Residencia_emisor,
    residence_country.name AS Pais_Nacimiento_emisor,
    recipient_country.name AS Pais_Residencia_receptor,
    states.name AS Nombre_Estado,
    t.status_neitcom,
    t.status_truora,
    u_sender.created_at AS Emisor_creado,
    u_recipient.created_at AS Receptor_creado

FROM transactions t
JOIN coincidencias c                       ON c.id = t.id
CROSS JOIN rango r
LEFT JOIN users u_sender                   ON t.sender_id      = u_sender.id
LEFT JOIN users u_recipient                ON t.recipient_id   = u_recipient.id
LEFT JOIN beneficiaries b                  ON t.beneficiary_id = b.id
LEFT JOIN users u_beneficiary              ON b.id = u_beneficiary.id
LEFT JOIN countries AS residence_country   ON residence_country.id = u_sender.residence_country_id
LEFT JOIN countries AS country             ON country.id = u_sender.country_id
LEFT JOIN countries AS recipient_country   ON recipient_country.id = u_recipient.country_id
LEFT JOIN states                           ON states.id = u_recipient.state_id
ORDER BY c.diferencia_monto NULLS LAST, t.created_at
LIMIT 500
;
