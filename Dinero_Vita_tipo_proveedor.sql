WITH params AS (
  SELECT
    '2026-09-11'::date AS from_date,  -- <<< inclusive
    '2026-09-12'::date AS to_date     -- <<< exclusive (mismo half-open [from, to) que usa la app)
),
scoped AS (
  SELECT
    a.category::int     AS category,
    a.external_provider  AS ep,
    CASE
      WHEN a.category = 4 THEN GREATEST(COALESCE(a.usd_amount::numeric, 0), COALESCE(b.usd_amount::numeric, 0))
      WHEN a.category = 6 THEN COALESCE(b.usd_amount::numeric, 0)
      ELSE a.usd_amount::numeric
    END AS usd
  FROM transactions a
  LEFT JOIN transactions b
    ON a.category IN (4, 6)
   AND b.id = a.dependent_transactions[1]::bigint
  CROSS JOIN params p
  WHERE a.created_at >= p.from_date
    AND a.created_at <  p.to_date
    AND (
      a.category NOT IN (4, 6)
      OR (a.category = 4 AND a.recipient_id = 1 AND a.sender_id <> 1)   -- leg A Exchange: cliente entrega
      OR (a.category = 6 AND a.sender_id IS NULL AND a.recipient_id = 1) -- leg A Payment: canónico
    )
),
cat_labels(category, label) AS (VALUES
  (0,  'Sent'), (1,  'Received'), (2,  'Deposit'), (3,  'Withdrawal'), (4,  'Exchange'),
  (5,  'Fee'), (6,  'Payment'), (7,  'Transfer'), (8,  'Vita Card'), (9,  'Tax'),
  (10, 'Cash Back Coupon'), (11, 'Service Payment'), (12, 'Adjustment'),
  (13, 'Card Credit Adjustment'), (14, 'Card Debit Adjustment'), (15, 'Card Transaction'),
  (16, 'Request Charge'), (17, 'Card Maintenance')
),
ep_labels(ep, label) AS (VALUES
  (0,'dLocal'), (1,'Wyre'), (2,'Ripple'), (3,'Manual'), (4,'Powwi'), (5,'Fintoc'),
  (6,'Transbank'), (7,'Floyd'), (8,'Binance'), (9,'Circle'), (10,'Reserve'),
  (11,'Bancolombia'), (12,'Floyd Heroes'), (13,'Bind'), (14,'Binance Pay'), (15,'Wompi'),
  (16,'Fortress'), (17,'Nium'), (18,'STP'), (19,'Sandya'), (20,'DFNS'), (21,'BCI'),
  (22,'Khipu'), (23,'Pagacel'), (24,'Skrill'), (25,'Alfin'), (26,'Pomelo'), (27,'Bridge'),
  (28,'Rendimento'), (29,'TransferSwap'), (30,'Bitso'), (31,'B89'), (32,'Occidente'),
  (33,'CBPay'), (34,'Sandya_API'), (35,'Checkbook'), (36,'Coopcentral'), (37,'Bind PSP'),
  (38,'Breb'), (39,'BVNK'), (40,'Redenlace')
)
SELECT
  s.category,
  COALESCE(cl.label, 'Cat ' || s.category)      AS categoria,
  s.ep,
  COALESCE(el.label, CASE WHEN s.ep IS NULL THEN 'sin proveedor' ELSE 'Provider ' || s.ep END) AS proveedor,
  COUNT(*)                                       AS transacciones,
  COALESCE(SUM(s.usd), 0)::numeric(18,2)         AS suma_usd
FROM scoped s
LEFT JOIN cat_labels cl ON cl.category = s.category
LEFT JOIN ep_labels  el ON el.ep = s.ep
GROUP BY s.category, cl.label, s.ep, el.label
ORDER BY s.category, transacciones DESC;