CREATE OR REPLACE PROCEDURE slastenin_food.add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status slastenin_food.product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
BEGIN
    IF p_rating IS NOT NULL THEN
        RAISE EXCEPTION 'У нового блюда до появления отзывов рейтинг должен быть NULL';
    END IF;

    INSERT INTO slastenin_food.product (
        restaurant_id, product_category_id, product_name, price,
        rating, status, description, photo_url
    ) VALUES (
        p_restaurant_id, p_product_category_id, p_name, p_price,
        p_rating, p_status, p_description, p_photo_url
    );
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Ресторан или категория блюда не существуют';
    WHEN check_violation OR not_null_violation THEN
        RAISE EXCEPTION 'Атрибуты блюда нарушают ограничения схемы';
END;
$$;

CREATE OR REPLACE FUNCTION slastenin_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
SET search_path = slastenin_food, pg_temp
AS $$
    WITH delivered_orders AS MATERIALIZED (
        SELECT order_id, restaurant_id, client_id, total_amount
        FROM slastenin_food."order" WHERE status = 'доставлен'
    ), order_totals AS (
        SELECT restaurant_id, sum(total_amount) AS total_amount, avg(total_amount) AS avg_amount
        FROM delivered_orders GROUP BY restaurant_id
    ), product_sales AS (
        SELECT d.restaurant_id, p.product_id, p.product_name, sum(s.quantity) AS quantity_sold
        FROM delivered_orders d
        JOIN slastenin_food.order_structure s USING (order_id)
        JOIN slastenin_food.product p USING (product_id)
        GROUP BY d.restaurant_id, p.product_id, p.product_name
    ), best_products AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, product_name
        FROM product_sales ORDER BY restaurant_id, quantity_sold DESC, random()
    ), client_orders AS (
        SELECT restaurant_id, client_id, count(*) AS order_count
        FROM delivered_orders GROUP BY restaurant_id, client_id
    ), best_clients AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, client_id
        FROM client_orders ORDER BY restaurant_id, order_count DESC, random()
    )
    SELECT r.restaurant_name, bp.product_name, ot.total_amount, ot.avg_amount, c.login
    FROM slastenin_food.restaurant r
    LEFT JOIN order_totals ot USING (restaurant_id)
    LEFT JOIN best_products bp USING (restaurant_id)
    LEFT JOIN best_clients bc USING (restaurant_id)
    LEFT JOIN slastenin_food.client c USING (client_id)
    ORDER BY r.restaurant_name;
$$;

CREATE OR REPLACE PROCEDURE slastenin_food.courier_salary()
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_month_start timestamp := date_trunc('month', localtimestamp);
    v_courier record;
    v_deliveries bigint;
    v_commission numeric;
    v_new_coefficient numeric(3,2);
BEGIN
    FOR v_courier IN SELECT courier_id, status, coefficient FROM slastenin_food.courier ORDER BY courier_id FOR UPDATE LOOP
        SELECT count(*), coalesce(sum(commission), 0)
        INTO v_deliveries, v_commission
        FROM slastenin_food."order"
        WHERE courier_id = v_courier.courier_id AND status = 'доставлен'
          AND order_timestamp >= v_month_start AND order_timestamp < v_month_start + interval '1 month';

        INSERT INTO slastenin_food.courier_pay AS existing_pay
            (year, month, courier_id, amount, coefficient_used)
        VALUES (extract(year FROM v_month_start)::integer, extract(month FROM v_month_start)::smallint,
            v_courier.courier_id, round(v_commission * v_courier.coefficient, 2), v_courier.coefficient)
        ON CONFLICT (year, month, courier_id) DO UPDATE
        SET amount = round(v_commission * existing_pay.coefficient_used, 2);

        IF v_courier.status <> 'уволен' THEN
            v_new_coefficient := CASE
                WHEN v_deliveries <= 150 THEN 0.10
                WHEN v_deliveries <= 250 THEN 0.20
                WHEN v_deliveries <= 500 THEN 0.30
                ELSE 0.50
            END;
            UPDATE slastenin_food.courier SET coefficient = v_new_coefficient
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW slastenin_food.how_much_money AS
WITH RECURSIVE bounds AS (
    SELECT date_trunc('month', min(order_timestamp)) AS first_month,
           date_trunc('month', max(order_timestamp)) AS last_month
    FROM slastenin_food."order" WHERE status = 'доставлен'
), months(month_start, last_month) AS (
    SELECT first_month, last_month FROM bounds WHERE first_month IS NOT NULL
    UNION ALL
    SELECT month_start + interval '1 month', last_month FROM months WHERE month_start < last_month
), order_totals AS (
    SELECT date_trunc('month', order_timestamp) AS month_start,
           sum(order_amount) AS sum_no_commission, sum(total_amount) AS sum_with_commission
    FROM slastenin_food."order" WHERE status = 'доставлен'
    GROUP BY date_trunc('month', order_timestamp)
), pay_totals AS (
    SELECT make_date(year, month, 1)::timestamp AS month_start, sum(amount) AS courier_pay
    FROM slastenin_food.courier_pay GROUP BY year, month
), month_values AS (
    SELECT m.month_start, coalesce(o.sum_no_commission, 0)::numeric AS sum_no_commission,
           coalesce(o.sum_with_commission, 0)::numeric AS sum_with_commission,
           (coalesce(o.sum_with_commission, 0) - coalesce(o.sum_no_commission, 0))::numeric AS commission,
           coalesce(p.courier_pay, 0)::numeric AS courier_pay
    FROM months m LEFT JOIN order_totals o USING (month_start) LEFT JOIN pay_totals p USING (month_start)
), lagged AS (
    SELECT *, lag(commission) OVER (ORDER BY month_start) AS prev_commission FROM month_values
)
SELECT to_char(month_start, 'YYYY-MM')::text AS year_month, sum_no_commission, sum_with_commission,
       commission, prev_commission, commission - prev_commission AS commission_diff,
       courier_pay, commission - courier_pay AS net_profit
FROM lagged;
