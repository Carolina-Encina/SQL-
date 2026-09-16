WITH cvu_info AS (
    SELECT 
        provider_accounts.user_id, 
        provider_accounts.account_number AS CVU, 
        provider_accounts.created_at AS cvu_created_at
    FROM provider_accounts
    INNER JOIN users ON users.id = provider_accounts.user_id
    WHERE 
        provider_accounts.provider_id = 1 
        AND provider_accounts.status = 1 
        AND provider_accounts.created_at <= to_timestamp('01/01/2029 23:59:59', 'MM/DD/YYYY HH24:MI:SS') 
        AND users.category = 0
)
SELECT DISTINCT
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
    cvu_sender.CVU AS Emisor_CVU,
    cvu_sender.cvu_created_at AS Emisor_CVU_created_at,
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
    cvu_recipient.CVU AS Receptor_CVU,
    cvu_recipient.cvu_created_at AS Receptor_CVU_created_at,
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
    (SELECT name FROM networks WHERE id = t.network_id) AS "Blockchain",
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
    cvu_beneficiary.CVU AS Beneficiario_CVU,
    cvu_beneficiary.cvu_created_at AS Beneficiario_CVU_created_at,
    u_beneficiary.secondary_document_number AS CUIT_Beneficiario,
    u_sender.accept_pep as is_pep,
    t.usd_amount AS Monto_en_USD,
    t.to_address,
    country.name AS Pais_Residencia_emisor,
    residence_country.name AS Pais_Nacimiento_emisor,
    recipient_country.name AS Pais_Residencia_receptor,
    states.name AS Nombre_Estado,
    t.status_neitcom,
t.status_truora,
u_sender.created_at,
u_recipient.created_at
FROM transactions t
LEFT JOIN users u_sender                   ON t.sender_id     = u_sender.id
LEFT JOIN users u_recipient                ON t.recipient_id  = u_recipient.id
LEFT JOIN cvu_info cvu_sender              ON cvu_sender.user_id    = u_sender.id
LEFT JOIN cvu_info cvu_recipient           ON cvu_recipient.user_id = u_recipient.id
LEFT JOIN beneficiaries b                  ON t.beneficiary_id = b.id
LEFT JOIN users u_beneficiary              ON b.id = u_beneficiary.id
LEFT JOIN cvu_info cvu_beneficiary         ON cvu_beneficiary.user_id = u_beneficiary.id
LEFT JOIN countries AS residence_country   ON residence_country.id = u_sender.residence_country_id
LEFT JOIN countries AS country             ON country.id = u_sender.country_id
LEFT JOIN countries AS recipient_country   ON recipient_country.id = u_recipient.country_id
LEFT JOIN states                           ON states.id = u_recipient.state_id
WHERE
  t.created_at BETWEEN '2026-08-31 00:00:00' AND '2026-08-31 23:59:59' -- YYYY-MM-DD
AND t.external_provider = 0
    ;