CREATE OR REPLACE FUNCTION slastenin_food.order_payment_status(p_order_id uuid)
RETURNS slastenin_food.order_pay_status
LANGUAGE sql
SET search_path = slastenin_food, pg_temp
AS $$
    SELECT (CASE
        WHEN bool_or(status = 'успех') THEN 'оплачен'
        WHEN bool_or(status = 'в_обработке') OR count(*) = 0 THEN 'ожидает'
        ELSE 'ошибка'
    END)::slastenin_food.order_pay_status
    FROM slastenin_food.payment WHERE order_id = p_order_id;
$$;

CREATE OR REPLACE FUNCTION slastenin_food.assert_order_for(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_order slastenin_food."order"%ROWTYPE;
    v_count bigint;
    v_amount numeric;
BEGIN
    SELECT * INTO v_order FROM slastenin_food."order" WHERE order_id = p_order_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT count(*), sum(round(quantity * unit_price, 2)) INTO v_count, v_amount
    FROM slastenin_food.order_structure WHERE order_id = p_order_id;
    IF v_count = 0 THEN
        RAISE EXCEPTION 'Заказ % должен содержать хотя бы одну позицию', p_order_id;
    END IF;
    IF v_amount <> v_order.order_amount THEN
        RAISE EXCEPTION 'Сумма заказа % должна совпадать с суммой округлённых позиций (%)', p_order_id, v_amount;
    END IF;
    IF EXISTS (
        SELECT 1 FROM slastenin_food.order_structure s
        JOIN slastenin_food.product p USING (product_id)
        WHERE s.order_id = p_order_id AND p.restaurant_id <> v_order.restaurant_id
    ) THEN
        RAISE EXCEPTION 'Все блюда должны принадлежать ресторану заказа %', p_order_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM slastenin_food.payment
        WHERE order_id = p_order_id AND amount <> v_order.total_amount
    ) THEN
        RAISE EXCEPTION 'Сумма каждой попытки оплаты должна совпадать с итогом заказа %', p_order_id;
    END IF;
    IF v_order.pay_status IS DISTINCT FROM slastenin_food.order_payment_status(p_order_id) THEN
        RAISE EXCEPTION 'Статус оплаты заказа % должен соответствовать попыткам оплаты', p_order_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM slastenin_food.review r
        WHERE r.order_id = p_order_id AND (
            (r.entity_type = 'ресторан' AND r.entity_id <> v_order.restaurant_id)
            OR (r.entity_type = 'блюдо' AND NOT EXISTS (
                SELECT 1 FROM slastenin_food.order_structure s
                WHERE s.order_id = r.order_id AND s.product_id = r.entity_id
            ))
        )
    ) THEN
        RAISE EXCEPTION 'Объект отзыва должен относиться к заказу %', p_order_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION slastenin_food.assert_order_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'product' THEN
        FOR v_order_id IN
            SELECT DISTINCT order_id FROM slastenin_food.order_structure
            WHERE product_id IN (OLD.product_id, NEW.product_id)
            ORDER BY order_id
        LOOP
            PERFORM slastenin_food.assert_order_for(v_order_id);
        END LOOP;
    ELSE
        IF TG_OP <> 'INSERT' THEN
            PERFORM slastenin_food.assert_order_for(OLD.order_id);
        END IF;
        IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.order_id IS DISTINCT FROM OLD.order_id) THEN
            PERFORM slastenin_food.assert_order_for(NEW.order_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION slastenin_food.prepare_order_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_old_order uuid;
    v_new_order uuid;
    v_order_id uuid;
    v_price numeric;
BEGIN
    IF TG_OP <> 'INSERT' THEN v_old_order := OLD.order_id; END IF;
    IF TG_OP <> 'DELETE' THEN v_new_order := NEW.order_id; END IF;

    IF TG_TABLE_NAME = 'order_structure' THEN
        IF TG_OP = 'UPDATE' THEN
            IF NEW.product_id IS DISTINCT FROM OLD.product_id
               OR NEW.unit_price IS DISTINCT FROM OLD.unit_price THEN
                RAISE EXCEPTION 'Нельзя менять блюдо или цену существующей позиции; создайте новую позицию';
            END IF;
        END IF;
        IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND v_old_order IS DISTINCT FROM v_new_order) THEN
            UPDATE slastenin_food.product SET price = price
            WHERE product_id = NEW.product_id RETURNING price INTO v_price;
            IF TG_OP = 'INSERT' THEN
                IF NEW.unit_price IS NULL THEN
                    NEW.unit_price := v_price;
                ELSIF v_price IS NOT NULL AND NEW.unit_price <> v_price THEN
                    RAISE EXCEPTION 'Цена позиции должна совпадать с текущей ценой блюда (%)', v_price;
                END IF;
            END IF;
        END IF;
    END IF;

    FOR v_order_id IN
        SELECT DISTINCT id FROM unnest(ARRAY[v_old_order, v_new_order]) AS ids(id)
        WHERE id IS NOT NULL ORDER BY id
    LOOP
        UPDATE slastenin_food."order" SET pay_status = pay_status WHERE order_id = v_order_id;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_prepare
BEFORE INSERT OR UPDATE OR DELETE ON slastenin_food.order_structure
FOR EACH ROW EXECUTE FUNCTION slastenin_food.prepare_order_change();
CREATE TRIGGER payment_prepare
BEFORE INSERT OR UPDATE OR DELETE ON slastenin_food.payment
FOR EACH ROW EXECUTE FUNCTION slastenin_food.prepare_order_change();
CREATE TRIGGER review_prepare
BEFORE INSERT OR UPDATE OR DELETE ON slastenin_food.review
FOR EACH ROW EXECUTE FUNCTION slastenin_food.prepare_order_change();

CREATE OR REPLACE FUNCTION slastenin_food.sync_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_old_order uuid;
    v_new_order uuid;
    v_order_id uuid;
    v_status slastenin_food.order_pay_status;
BEGIN
    IF TG_OP <> 'INSERT' THEN v_old_order := OLD.order_id; END IF;
    IF TG_OP <> 'DELETE' THEN v_new_order := NEW.order_id; END IF;
    FOR v_order_id IN
        SELECT DISTINCT id FROM unnest(ARRAY[v_old_order, v_new_order]) AS ids(id)
        WHERE id IS NOT NULL ORDER BY id
    LOOP
        v_status := slastenin_food.order_payment_status(v_order_id);
        UPDATE slastenin_food."order" SET pay_status = v_status
        WHERE order_id = v_order_id AND pay_status IS DISTINCT FROM v_status;
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_order_status
AFTER INSERT OR UPDATE OR DELETE ON slastenin_food.payment
FOR EACH ROW EXECUTE FUNCTION slastenin_food.sync_order_pay_status();

CREATE OR REPLACE FUNCTION slastenin_food.protect_order_address()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
BEGIN
    IF TG_TABLE_NAME = 'order' THEN
        UPDATE slastenin_food.address SET street = street WHERE address_id = NEW.address_id;
    ELSIF (NEW.street, NEW.house_number, NEW.apartment_office)
          IS DISTINCT FROM (OLD.street, OLD.house_number, OLD.apartment_office) THEN
        IF EXISTS (SELECT 1 FROM slastenin_food."order" WHERE address_id = OLD.address_id) THEN
            RAISE EXCEPTION 'Нельзя изменить адрес, использованный в заказе; создайте новый адрес';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_address_lock
BEFORE INSERT OR UPDATE OF address_id ON slastenin_food."order"
FOR EACH ROW EXECUTE FUNCTION slastenin_food.protect_order_address();
CREATE TRIGGER address_history_check
BEFORE UPDATE OF street, house_number, apartment_office ON slastenin_food.address
FOR EACH ROW EXECUTE FUNCTION slastenin_food.protect_order_address();

CREATE CONSTRAINT TRIGGER order_consistency_check
AFTER INSERT OR UPDATE ON slastenin_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION slastenin_food.assert_order_change();
CREATE CONSTRAINT TRIGGER order_structure_consistency_check
AFTER INSERT OR UPDATE OR DELETE ON slastenin_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION slastenin_food.assert_order_change();
CREATE CONSTRAINT TRIGGER payment_consistency_check
AFTER INSERT OR UPDATE OR DELETE ON slastenin_food.payment
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION slastenin_food.assert_order_change();
CREATE CONSTRAINT TRIGGER review_consistency_check
AFTER INSERT OR UPDATE OR DELETE ON slastenin_food.review
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION slastenin_food.assert_order_change();
CREATE CONSTRAINT TRIGGER product_orders_consistency_check
AFTER UPDATE OF restaurant_id, product_id ON slastenin_food.product
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION slastenin_food.assert_order_change();

CREATE OR REPLACE FUNCTION slastenin_food.refresh_review_rating(
    p_entity_type slastenin_food.review_entity_type, p_entity_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
DECLARE
    v_rating numeric(3,2);
BEGIN
    IF p_entity_type NOT IN ('блюдо', 'ресторан') THEN RETURN; END IF;
    SELECT round(avg(rating), 2) INTO v_rating FROM slastenin_food.review
    WHERE entity_type = p_entity_type AND entity_id = p_entity_id;
    IF p_entity_type = 'блюдо' THEN
        UPDATE slastenin_food.product SET rating = v_rating WHERE product_id = p_entity_id;
    ELSE
        UPDATE slastenin_food.restaurant SET rating = v_rating WHERE restaurant_id = p_entity_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION slastenin_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = slastenin_food, pg_temp
AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        PERFORM slastenin_food.refresh_review_rating(OLD.entity_type, OLD.entity_id);
    END IF;
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND
        (NEW.entity_type, NEW.entity_id) IS DISTINCT FROM (OLD.entity_type, OLD.entity_id)) THEN
        PERFORM slastenin_food.refresh_review_rating(NEW.entity_type, NEW.entity_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER review_rating_change
AFTER INSERT OR UPDATE OR DELETE ON slastenin_food.review
FOR EACH ROW EXECUTE FUNCTION slastenin_food.rating_change();
