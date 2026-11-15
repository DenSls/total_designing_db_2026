DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2026';
    ELSE
        ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2026';
    END IF;
END;
$$;

GRANT ALL PRIVILEGES ON SCHEMA slastenin_food TO inspector;
GRANT USAGE ON SCHEMA exts, information_schema, pg_catalog TO inspector;
GRANT USAGE ON TYPE slastenin_food.restaurant_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.product_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.courier_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.order_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.order_pay_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.payment_status TO inspector;
GRANT USAGE ON TYPE slastenin_food.payment_type TO inspector;
GRANT USAGE ON TYPE slastenin_food.review_entity_type TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA slastenin_food TO inspector;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA slastenin_food TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA slastenin_food TO inspector;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA slastenin_food TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;

ALTER DEFAULT PRIVILEGES IN SCHEMA slastenin_food
    GRANT ALL PRIVILEGES ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA slastenin_food
    GRANT USAGE, SELECT ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA slastenin_food
    GRANT USAGE ON TYPES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA slastenin_food
    GRANT EXECUTE ON FUNCTIONS TO inspector;
