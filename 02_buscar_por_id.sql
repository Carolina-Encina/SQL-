-- =============================================================================
-- 02 · Buscar por ID
-- -----------------------------------------------------------------------------
-- Busca uno o varios IDs y dice por qué campo coincidió cada resultado
-- (columna "Coincide_por"). Sirve para cualquier ID que aparezca en la app,
-- la cartola o el reporte del proveedor:
--   * ID de transacción Vita (ej.: 5875934)
--   * ID público (UUID, ej.: 58ace3fc-...)
--   * ID externo, con o sin prefijo admn_ / usr_. Ejemplos:
--       Fintoc:      pi_3JxLM0Ugaafodq9CSOZBVk6EEHw
--       BIND PSP:    referencia de 22 caracteres de la cartola (PDX4OGNY48...)
--       Bancolombia: COBC202609112344-5488942
--       Bind:        NSBT-1-1-759667-..., 1-30717447243-...
--   * UUID de una orden de pago (payment order) que aparece en la descripción
--
-- Además trae las filas "hermanas" del mismo ID externo base (en los enlaces
-- de pago: "Incoming transaction" + "Deposit transaction to user"), para no
-- confundir un pago con dos.
--
-- Qué editar:
--   1. La lista "ids_buscados": un valor por fila, siempre entre comillas.
--   2. zona: para ver la hora local del banco en la columna Fecha_local.
--   3. (Opcional) desde/hasta: solo limitan la búsqueda dentro de la
--      descripción, que es la parte lenta.
-- =============================================================================

WITH parametros AS (
    SELECT
        'America/Santiago'              AS zona,
        TIMESTAMP '2026-09-01 00:00:00' AS desde_utc_descripcion,
        TIMESTAMP '2026-10-31 23:59:59' AS hasta_utc_descripcion
),
ids_buscados(valor) AS (
    VALUES
        ('5875934'),
        ('pi_3JxLM0Ugaafodq9CSOZBVk6EEHw'),
        ('PDX4OGNY48E4RL3Y20L6EY')
),
ids_limpios AS (
    SELECT
        TRIM(valor) AS valor,
        REGEXP_REPLACE(TRIM(valor), '^(admn_|usr_)', '') AS valor_sin_prefijo
    FROM ids_buscados
),
directas AS (
    -- ID de transacción
    SELECT t.id, 'ID de transacción = ' || i.valor AS motivo
    FROM transactions t JOIN ids_limpios i ON t.id::text = i.valor
    UNION ALL
    -- ID público
    SELECT t.id, 'ID público = ' || i.valor
    FROM transactions t JOIN ids_limpios i ON t.alt_id::text = i.valor
    UNION ALL
    -- ID externo exacto, o con/sin prefijo admn_ / usr_
    SELECT t.id, 'ID externo = ' || t.external_id
    FROM transactions t JOIN ids_limpios i
      ON t.external_id IN (i.valor, i.valor_sin_prefijo,
                           'admn_' || i.valor_sin_prefijo,
                           'usr_'  || i.valor_sin_prefijo)
    UNION ALL
    -- Texto dentro de la descripción (UUID de orden de pago, etc.), solo en el rango
    SELECT t.id, 'Descripción contiene ' || i.valor
    FROM transactions t
    JOIN ids_limpios i ON LENGTH(i.valor) >= 8
    CROSS JOIN parametros p
    WHERE t.created_at BETWEEN p.desde_utc_descripcion AND p.hasta_utc_descripcion
      AND t.description ILIKE '%' || i.valor || '%'
),
bases AS (
    -- ID externo base de lo encontrado, para traer sus filas hermanas
    SELECT DISTINCT REGEXP_REPLACE(t.external_id, '^(admn_|usr_)', '') AS ext_base
    FROM transactions t
    JOIN directas d ON d.id = t.id
    WHERE COALESCE(t.external_id, '') <> ''
),
hermanas AS (
    SELECT t.id, 'Mismo ID externo base (fila hermana)' AS motivo
    FROM transactions t
    JOIN bases o ON t.external_id IN ('admn_' || o.ext_base, 'usr_' || o.ext_base, o.ext_base)
),
coincidencias AS (
    SELECT id, STRING_AGG(DISTINCT motivo, ' | ') AS coincide_por
    FROM (SELECT * FROM directas UNION ALL SELECT * FROM hermanas) x
    GROUP BY id
)
SELECT DISTINCT
    c.coincide_por AS Coincide_por,
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
CROSS JOIN parametros r
LEFT JOIN users u_sender                   ON t.sender_id      = u_sender.id
LEFT JOIN users u_recipient                ON t.recipient_id   = u_recipient.id
LEFT JOIN beneficiaries b                  ON t.beneficiary_id = b.id
LEFT JOIN users u_beneficiary              ON b.id = u_beneficiary.id
LEFT JOIN countries AS residence_country   ON residence_country.id = u_sender.residence_country_id
LEFT JOIN countries AS country             ON country.id = u_sender.country_id
LEFT JOIN countries AS recipient_country   ON recipient_country.id = u_recipient.country_id
LEFT JOIN states                           ON states.id = u_recipient.state_id
ORDER BY t.created_at
;

-- -----------------------------------------------------------------------------
-- Si no aparece nada:
--   * El número puede ser el ID de un usuario y no de una transacción. Usa el
--     archivo 03 con usuario_id = ese número y un rango de fechas.
--   * El movimiento puede existir con otro monto, otra hora u otro proveedor:
--     usa el archivo 03 (monto con tolerancia, RUT/DNI/CUIT, nombre, cuenta)
--     o el 04 (candidatos por monto y hora del banco, todos los proveedores).
-- -----------------------------------------------------------------------------
