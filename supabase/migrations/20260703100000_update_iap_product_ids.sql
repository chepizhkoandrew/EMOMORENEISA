UPDATE app_config
SET value = jsonb_set(
  value,
  '{treat_packs}',
  (
    SELECT jsonb_agg(
      CASE
        WHEN pack->>'product_id' = 'treats_599'  THEN pack || '{"product_id":"treats_starter_599"}'
        WHEN pack->>'product_id' = 'treats_1199' THEN pack || '{"product_id":"treats_plus_1199"}'
        WHEN pack->>'product_id' = 'treats_2499' THEN pack || '{"product_id":"treats_pro_2499"}'
        ELSE pack
      END
    )
    FROM jsonb_array_elements(value->'treat_packs') AS pack
    WHERE pack->>'product_id' != 'treats_4999'
  )
)
WHERE key = 'billing';
