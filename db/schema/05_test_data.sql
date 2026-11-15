CREATE OR REPLACE PROCEDURE slastenin_food.erase_test_data()
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
BEGIN
    DELETE FROM slastenin_food.review;
    DELETE FROM slastenin_food.payment;
    DELETE FROM slastenin_food.order_structure;
    DELETE FROM slastenin_food.courier_pay;
    DELETE FROM slastenin_food."order";
    DELETE FROM slastenin_food.client_address;
    DELETE FROM slastenin_food.product;
    DELETE FROM slastenin_food.restaurant;
    DELETE FROM slastenin_food.legal_entity;
    DELETE FROM slastenin_food.client;
    DELETE FROM slastenin_food.courier;
    DELETE FROM slastenin_food.product_category;
    DELETE FROM slastenin_food.address;
END;
$$;

CREATE SEQUENCE IF NOT EXISTS slastenin_food.test_data_number
    AS bigint MAXVALUE 999999999 NO CYCLE;

CREATE OR REPLACE PROCEDURE slastenin_food.insert_test_data(value integer)
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    i integer;
    j integer;
    v_count integer;
    v_number bigint;
    v_id uuid;
    v_order_id uuid;
    v_client_idx integer;
    v_restaurant_idx integer;
    v_address_idx integer;
    v_courier_idx integer;
    v_product_idx integer;
    v_now timestamp := localtimestamp;
    v_first_month timestamp := date_trunc('month', v_now) - interval '5 months';
    v_month timestamp;
    v_order_timestamp timestamp;
    v_delivery_timestamp timestamp;
    v_amount numeric;
    v_review_type slastenin_food.review_entity_type;
    v_rating integer;
    v_courier_status slastenin_food.courier_status;
    v_total numeric;
    v_coefficient numeric(3,2);
    v_deliveries integer;
    v_commission numeric;
    v_clients uuid[] := ARRAY[]::uuid[];
    v_couriers uuid[] := ARRAY[]::uuid[];
    v_owners uuid[] := ARRAY[]::uuid[];
    v_restaurants uuid[] := ARRAY[]::uuid[];
    v_categories uuid[] := ARRAY[]::uuid[];
    v_addresses uuid[] := ARRAY[]::uuid[];
    v_products uuid[] := ARRAY[]::uuid[];
    v_restaurant_statuses slastenin_food.restaurant_status[] := enum_range(NULL::slastenin_food.restaurant_status);
    v_product_statuses slastenin_food.product_status[] := enum_range(NULL::slastenin_food.product_status);
    v_courier_statuses slastenin_food.courier_status[] := enum_range(NULL::slastenin_food.courier_status);
    v_order_statuses slastenin_food.order_status[] := enum_range(NULL::slastenin_food.order_status);
    v_payment_statuses slastenin_food.payment_status[] := enum_range(NULL::slastenin_food.payment_status);
    v_payment_types slastenin_food.payment_type[] := enum_range(NULL::slastenin_food.payment_type);
    v_review_types slastenin_food.review_entity_type[] := enum_range(NULL::slastenin_food.review_entity_type);
    v_streets text[] := ARRAY['Лесная', 'Садовая', 'Центральная', 'Зелёная', 'Набережная'];
    v_names text[] := ARRAY['Александр', 'Иван', 'Дмитрий', 'Максим', 'Андрей'];
    v_surnames text[] := ARRAY['Иванов', 'Петров', 'Соколов', 'Смирнов', 'Кузнецов'];
    v_restaurant_names text[] := ARRAY['Тёплый хлеб', 'Семейный стол', 'Вкусный двор', 'Ложка и вилка', 'Домашняя кухня'];
    v_product_names text[] := ARRAY['Борщ со сметаной', 'Салат из овощей', 'Шашлык из курицы (кг)', 'Пельмени', 'Сырники'];
    v_middle_names text[] := ARRAY['Александрович', 'Иванович', 'Дмитриевич', 'Максимович', 'Андреевич'];
    v_logins text[] := ARRAY['alex', 'ivan', 'dmitry', 'maxim', 'andrey'];
    v_login_surnames text[] := ARRAY['ivanov', 'petrov', 'sokolov', 'smirnov', 'kuznetsov'];
    v_categories_names text[] := ARRAY['Домашняя кухня', 'Обеды', 'Блюда на каждый день', 'Семейное меню', 'Авторская кухня'];
    v_restaurant_descriptions text[] := ARRAY[
        'Супы, горячие блюда и выпечка по домашним рецептам.',
        'Сезонные продукты, блюда на гриле и свежие салаты.',
        'Завтраки, сытные обеды и десерты к чаю.'
    ];
    v_order_notes text[] := ARRAY[
        'Позвоните перед приездом.', 'Положите столовые приборы.',
        'Соус упакуйте отдельно.', 'Передайте заказ у входа.', 'Приборы не нужны.'
    ];
    v_review_notes text[] := ARRAY[
        'Ожидал лучшего качества, впечатление неудачное.',
        'Есть замечания к качеству и оформлению.',
        'В целом неплохо, но есть что улучшить.',
        'Хорошее впечатление, почти всё понравилось.',
        'Всё отлично, с удовольствием закажу снова.'
    ];
    v_product_descriptions text[] := ARRAY[
        'Свёкла, капуста, картофель, говядина и сметана.',
        'Свежие огурцы, помидоры, зелень и растительное масло.',
        'Курица на углях с луком и зеленью. Цена за килограмм.',
        'Пельмени с мясной начинкой, подаются со сметаной.',
        'Творожные сырники со сметаной и ягодным соусом.'
    ];
BEGIN
    IF value IS NULL OR value < 1 OR value > 2147483647 / 5 THEN
        RAISE EXCEPTION 'Значение value должно быть от 1 до 429496729';
    END IF;
    v_count := value * 5;

    SELECT array_agg(v_courier_statuses[1 + (n - 1) % cardinality(v_courier_statuses)] ORDER BY random())
    INTO v_courier_statuses FROM generate_series(1, value) n;
    SELECT array_agg(v_restaurant_statuses[1 + (n - 1) % cardinality(v_restaurant_statuses)] ORDER BY random())
    INTO v_restaurant_statuses FROM generate_series(1, value) n;
    SELECT array_agg(v_product_statuses[1 + (n - 1) % cardinality(v_product_statuses)] ORDER BY random())
    INTO v_product_statuses FROM generate_series(1, v_count) n;
    SELECT array_agg(v_order_statuses[1 + (n - 1) % cardinality(v_order_statuses)] ORDER BY random())
    INTO v_order_statuses FROM generate_series(1, v_count) n;
    SELECT array_agg(v_payment_statuses[1 + (n - 1) % cardinality(v_payment_statuses)] ORDER BY random())
    INTO v_payment_statuses FROM generate_series(1, v_count) n;
    SELECT array_agg(v_payment_types[1 + (n - 1) % cardinality(v_payment_types)] ORDER BY random())
    INTO v_payment_types FROM generate_series(1, v_count) n;
    SELECT array_agg(v_review_types[1 + (n - 1) % cardinality(v_review_types)] ORDER BY random())
    INTO v_review_types FROM generate_series(1, v_count) n;

    FOR i IN 1..value LOOP
        v_number := nextval('slastenin_food.test_data_number');
        INSERT INTO client(login, password, phone_number)
        VALUES (
            v_logins[1 + floor(random() * cardinality(v_logins))::integer] || '.' ||
            v_login_surnames[1 + floor(random() * cardinality(v_login_surnames))::integer] || v_number,
            md5(random()::text), '+79' || lpad(v_number::text, 9, '0')
        )
        RETURNING client_id INTO v_id;

        v_clients := array_append(v_clients, v_id);

        INSERT INTO courier(last_name, first_name, middle_name, phone_number, status, hire_date, dismissal_date)
        VALUES (
            v_surnames[1 + floor(random() * cardinality(v_surnames))::integer],
            v_names[1 + floor(random() * cardinality(v_names))::integer],
            CASE WHEN i % 3 = 0 THEN NULL ELSE v_middle_names[1 + floor(random() * cardinality(v_middle_names))::integer] END,
            '+79' || lpad(v_number::text, 9, '0'), v_courier_statuses[i], v_first_month::date,
            CASE WHEN v_courier_statuses[i] = 'уволен' THEN v_now::date ELSE NULL END
        ) RETURNING courier_id INTO v_id;
        v_couriers := array_append(v_couriers, v_id);

        INSERT INTO product_category(product_category_name)
        VALUES (v_categories_names[1 + floor(random() * cardinality(v_categories_names))::integer])
        RETURNING product_category_id INTO v_id;
        v_categories := array_append(v_categories, v_id);

        v_number := nextval('slastenin_food.test_data_number');
        INSERT INTO legal_entity(inn, ogrn)
        VALUES ('7' || lpad(v_number::text, 9, '0'), '1000' || lpad(v_number::text, 9, '0'))
        RETURNING legal_entity_id INTO v_id;

        v_owners := array_append(v_owners, v_id);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_number := nextval('slastenin_food.test_data_number');
        INSERT INTO address(street, house_number, apartment_office)
        VALUES (
            v_streets[1 + floor(random() * cardinality(v_streets))::integer],
            v_number::text, CASE WHEN i % 4 = 0 THEN NULL ELSE (1 + i % 100)::text END
        ) RETURNING address_id INTO v_id;

        v_addresses := array_append(v_addresses, v_id);
    END LOOP;

    FOR i IN 1..value LOOP
        INSERT INTO restaurant(
            restaurant_name, address_id, legal_entity_id, settlement_account,
            description, work_start, work_end, status
        ) VALUES (
            v_restaurant_names[1 + floor(random() * cardinality(v_restaurant_names))::integer],
            v_addresses[i], v_owners[i],
            '40702810' || lpad(nextval('slastenin_food.test_data_number')::text, 12, '0'),
            v_restaurant_descriptions[1 + floor(random() * cardinality(v_restaurant_descriptions))::integer],
            time '09:00', time '22:00', v_restaurant_statuses[i]
        ) RETURNING restaurant_id INTO v_id;
        v_restaurants := array_append(v_restaurants, v_id);
    END LOOP;

    FOR i IN 1..(value * 4) LOOP
        INSERT INTO client_address(client_id, address_id)
        VALUES (v_clients[1 + (i - 1) % value], v_addresses[value + i]);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_restaurant_idx := (i - 1) / 5 + 1;
        j := 1 + floor(random() * cardinality(v_product_names))::integer;
        INSERT INTO product(
            product_name, product_category_id, restaurant_id, price, description, photo_url, status
        ) VALUES (
            v_product_names[j], v_categories[v_restaurant_idx], v_restaurants[v_restaurant_idx],
            1000 + (i % 10) * 100, v_product_descriptions[j],
            CASE WHEN i % 3 = 0 THEN NULL ELSE 'https://example.com/food/dish-' || j || '.jpg' END,
            v_product_statuses[i]
        ) RETURNING product_id INTO v_id;
        v_products := array_append(v_products, v_id);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_restaurant_idx := (i - 1) / 5 + 1;
        v_address_idx := value + 1 + (i - 1) % (value * 4);
        v_client_idx := 1 + (v_address_idx - value - 1) % value;
        v_courier_idx := 1 + (i - 1) % value;
        v_product_idx := (v_restaurant_idx - 1) * 5 + 1 + (i - 1) % 5;
        v_month := v_first_month + ((i - 1) % 6) * interval '1 month';
        v_order_timestamp := v_month + random() * (least(v_month + interval '1 month', v_now) - v_month);
        v_delivery_timestamp := least(v_order_timestamp + interval '30 minutes', v_now);
        SELECT price INTO v_amount FROM product WHERE product_id = v_products[v_product_idx];

        INSERT INTO slastenin_food."order"(
            client_id, restaurant_id, courier_id, address_id, order_timestamp,
            delivery_timestamp, order_amount, status, description
        ) VALUES (
            v_clients[v_client_idx], v_restaurants[v_restaurant_idx], v_couriers[v_courier_idx],
            v_addresses[v_address_idx], v_order_timestamp,
            CASE WHEN v_order_statuses[i] = 'доставлен' THEN v_delivery_timestamp ELSE NULL END, v_amount,
            v_order_statuses[i], v_order_notes[1 + floor(random() * cardinality(v_order_notes))::integer]
        ) RETURNING order_id, total_amount INTO v_order_id, v_total;

        INSERT INTO order_structure(order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, v_products[v_product_idx], 1, v_amount);

        INSERT INTO payment(order_id, type, amount, transaction_id, transaction_timestamp, status)
        VALUES (v_order_id, v_payment_types[i],
            v_total, exts.uuid_generate_v4()::text, v_order_timestamp, v_payment_statuses[i]);

        v_review_type := v_review_types[i];
        v_rating := 1 + floor(random() * 5)::integer;
        INSERT INTO review(order_id, client_id, entity_type, entity_id, review_timestamp, description, photo_url, rating)
        VALUES (
            v_order_id, v_clients[v_client_idx], v_review_type,
            CASE v_review_type WHEN 'блюдо' THEN v_products[v_product_idx]
                WHEN 'ресторан' THEN v_restaurants[v_restaurant_idx] ELSE v_order_id END,
            least(v_delivery_timestamp + interval '1 hour', v_now), v_review_notes[v_rating],
            CASE WHEN i % 4 = 0 THEN NULL ELSE 'https://example.com/food/review-' || v_order_id || '.jpg' END,
            v_rating
        );
    END LOOP;

    FOR i IN 1..value LOOP
        v_coefficient := 0.10;
        v_courier_status := v_courier_statuses[i];
        FOR j IN 0..5 LOOP
            v_month := v_first_month + j * interval '1 month';
            SELECT count(*)::integer, coalesce(sum(commission), 0)
            INTO v_deliveries, v_commission
            FROM slastenin_food."order"
            WHERE courier_id = v_couriers[i] AND status = 'доставлен'
              AND order_timestamp >= v_month AND order_timestamp < v_month + interval '1 month';

            INSERT INTO courier_pay(year, month, courier_id, amount, coefficient_used)
            VALUES (extract(year FROM v_month)::integer, extract(month FROM v_month)::smallint,
                v_couriers[i], round(v_commission * v_coefficient, 2), v_coefficient);

            IF j < 5 OR v_courier_status <> 'уволен' THEN
                v_coefficient := CASE WHEN v_deliveries <= 150 THEN 0.10
                    WHEN v_deliveries <= 250 THEN 0.20 WHEN v_deliveries <= 500 THEN 0.30 ELSE 0.50 END;
            END IF;
        END LOOP;
        UPDATE courier SET coefficient = v_coefficient WHERE courier_id = v_couriers[i];
    END LOOP;
END;
$$;
