CREATE TABLE slastenin_food.client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(50) NOT NULL,
    password varchar(32) NOT NULL,
    phone_number varchar(16) NOT NULL,
    CONSTRAINT uq_client_login UNIQUE (login),
    CONSTRAINT uq_client_phone UNIQUE (phone_number),
    CONSTRAINT ck_client_login CHECK (btrim(login) <> ''),
    CONSTRAINT ck_client_password CHECK (password ~ '^[0-9a-f]{32}$'),
    CONSTRAINT ck_client_phone CHECK (btrim(phone_number) <> '')
);

CREATE TABLE slastenin_food.address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(150) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(20),
    CONSTRAINT uq_address_location UNIQUE NULLS NOT DISTINCT
        (street, house_number, apartment_office),
    CONSTRAINT ck_address_street CHECK (btrim(street) <> ''),
    CONSTRAINT ck_address_house CHECK (btrim(house_number) <> ''),
    CONSTRAINT ck_address_apartment CHECK (apartment_office IS NULL OR btrim(apartment_office) <> '')
);

CREATE TABLE slastenin_food.client_address (
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    PRIMARY KEY (client_id, address_id),
    CONSTRAINT fk_client_address_client FOREIGN KEY (client_id)
        REFERENCES slastenin_food.client (client_id),
    CONSTRAINT fk_client_address_address FOREIGN KEY (address_id)
        REFERENCES slastenin_food.address (address_id)
);

CREATE TABLE slastenin_food.legal_entity (
    legal_entity_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    inn varchar(12) NOT NULL,
    ogrn varchar(15) NOT NULL,
    CONSTRAINT uq_legal_entity_inn UNIQUE (inn),
    CONSTRAINT uq_legal_entity_ogrn UNIQUE (ogrn),
    CONSTRAINT ck_legal_entity_details CHECK (btrim(inn) <> '' AND btrim(ogrn) <> '')
);

CREATE TABLE slastenin_food.restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id uuid NOT NULL,
    legal_entity_id uuid NOT NULL,
    settlement_account varchar(20) NOT NULL,
    description varchar(500) NOT NULL,
    work_start time without time zone NOT NULL,
    work_end time without time zone NOT NULL,
    rating numeric(3,2),
    status slastenin_food.restaurant_status NOT NULL,
    CONSTRAINT uq_restaurant_address UNIQUE (address_id),
    CONSTRAINT fk_restaurant_address FOREIGN KEY (address_id)
        REFERENCES slastenin_food.address (address_id),
    CONSTRAINT fk_restaurant_legal_entity FOREIGN KEY (legal_entity_id)
        REFERENCES slastenin_food.legal_entity (legal_entity_id),
    CONSTRAINT ck_restaurant_text CHECK (
        btrim(restaurant_name) <> '' AND btrim(settlement_account) <> '' AND btrim(description) <> ''
    ),
    CONSTRAINT ck_restaurant_hours CHECK (work_end > work_start),
    CONSTRAINT ck_restaurant_rating CHECK (rating BETWEEN 0 AND 5)
);

CREATE TABLE slastenin_food.courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    last_name varchar(80) NOT NULL,
    first_name varchar(80) NOT NULL,
    middle_name varchar(80),
    phone_number varchar(16) NOT NULL,
    status slastenin_food.courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(3,2) NOT NULL DEFAULT 0.10,
    CONSTRAINT ck_courier_name CHECK (
        btrim(last_name) <> '' AND btrim(first_name) <> ''
        AND (middle_name IS NULL OR btrim(middle_name) <> '')
    ),
    CONSTRAINT ck_courier_phone CHECK (btrim(phone_number) <> ''),
    CONSTRAINT ck_courier_coefficient CHECK (coefficient BETWEEN 0.10 AND 0.50),
    CONSTRAINT ck_courier_dates CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date),
    CONSTRAINT ck_courier_dismissal CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL)
);

CREATE TABLE slastenin_food.courier_pay (
    year integer NOT NULL,
    month smallint NOT NULL,
    courier_id uuid NOT NULL,
    amount numeric(8,2) NOT NULL,
    coefficient_used numeric(3,2) NOT NULL,
    PRIMARY KEY (year, month, courier_id),
    CONSTRAINT fk_courier_pay_courier FOREIGN KEY (courier_id)
        REFERENCES slastenin_food.courier (courier_id),
    CONSTRAINT ck_courier_pay_year CHECK (year BETWEEN 1 AND 9999),
    CONSTRAINT ck_courier_pay_month CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT ck_courier_pay_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT ck_courier_pay_coefficient CHECK (coefficient_used BETWEEN 0.10 AND 0.50)
);

CREATE TABLE slastenin_food.product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(80) NOT NULL,
    CONSTRAINT ck_product_category_name CHECK (btrim(product_category_name) <> '')
);

CREATE TABLE slastenin_food.product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(100) NOT NULL,
    product_category_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    price numeric(6,2) NOT NULL,
    description varchar(500) NOT NULL,
    photo_url varchar(255),
    rating numeric(3,2),
    status slastenin_food.product_status NOT NULL,
    CONSTRAINT fk_product_restaurant FOREIGN KEY (restaurant_id)
        REFERENCES slastenin_food.restaurant (restaurant_id),
    CONSTRAINT fk_product_category FOREIGN KEY (product_category_id)
        REFERENCES slastenin_food.product_category (product_category_id),
    CONSTRAINT ck_product_text CHECK (
        btrim(product_name) <> '' AND btrim(description) <> ''
        AND (photo_url IS NULL OR btrim(photo_url) <> '')
    ),
    CONSTRAINT ck_product_price CHECK (price >= 0 AND price <> 'NaN'::numeric),
    CONSTRAINT ck_product_rating CHECK (rating BETWEEN 0 AND 5)
);

CREATE TABLE slastenin_food."order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    courier_id uuid NOT NULL,
    address_id uuid NOT NULL,
    order_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp without time zone,
    order_amount numeric(8,2) NOT NULL,
    commission numeric(8,2)
        GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED NOT NULL,
    total_amount numeric(8,2)
        GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED NOT NULL,
    status slastenin_food.order_status NOT NULL DEFAULT 'создан',
    pay_status slastenin_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description varchar(500) NOT NULL,
    CONSTRAINT uq_order_client UNIQUE (order_id, client_id),
    CONSTRAINT fk_order_client FOREIGN KEY (client_id)
        REFERENCES slastenin_food.client (client_id),
    CONSTRAINT fk_order_restaurant FOREIGN KEY (restaurant_id)
        REFERENCES slastenin_food.restaurant (restaurant_id),
    CONSTRAINT fk_order_courier FOREIGN KEY (courier_id)
        REFERENCES slastenin_food.courier (courier_id),
    CONSTRAINT fk_order_address FOREIGN KEY (address_id)
        REFERENCES slastenin_food.address (address_id),
    CONSTRAINT fk_order_client_address FOREIGN KEY (client_id, address_id)
        REFERENCES slastenin_food.client_address (client_id, address_id),
    CONSTRAINT ck_order_description CHECK (btrim(description) <> ''),
    CONSTRAINT ck_order_amount CHECK (order_amount >= 0 AND order_amount <> 'NaN'::numeric),
    CONSTRAINT ck_order_minimum CHECK (total_amount >= 1000),
    CONSTRAINT ck_order_dates CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT ck_order_delivery CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)
);

CREATE TABLE slastenin_food.order_structure (
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(8,3) NOT NULL,
    unit_price numeric(6,2) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT fk_order_structure_order FOREIGN KEY (order_id)
        REFERENCES slastenin_food."order" (order_id),
    CONSTRAINT fk_order_structure_product FOREIGN KEY (product_id)
        REFERENCES slastenin_food.product (product_id),
    CONSTRAINT ck_order_structure_quantity CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    CONSTRAINT ck_order_structure_price CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric)
);

CREATE TABLE slastenin_food.payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL,
    type slastenin_food.payment_type NOT NULL,
    amount numeric(8,2) NOT NULL,
    transaction_id varchar(100) NOT NULL,
    transaction_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    status slastenin_food.payment_status NOT NULL,
    CONSTRAINT uq_payment_transaction UNIQUE (transaction_id),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id)
        REFERENCES slastenin_food."order" (order_id),
    CONSTRAINT ck_payment_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT ck_payment_transaction CHECK (btrim(transaction_id) <> '')
);

CREATE UNIQUE INDEX uq_payment_one_success
    ON slastenin_food.payment (order_id) WHERE status = 'успех';

CREATE TABLE slastenin_food.review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL,
    client_id uuid NOT NULL,
    entity_type slastenin_food.review_entity_type NOT NULL,
    entity_id uuid NOT NULL,
    review_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    description varchar(500) NOT NULL,
    photo_url varchar(255),
    rating numeric(3,2) NOT NULL,
    CONSTRAINT uq_review_order_target UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT fk_review_order FOREIGN KEY (order_id)
        REFERENCES slastenin_food."order" (order_id),
    CONSTRAINT fk_review_client FOREIGN KEY (client_id)
        REFERENCES slastenin_food.client (client_id),
    CONSTRAINT fk_review_order_client FOREIGN KEY (order_id, client_id)
        REFERENCES slastenin_food."order" (order_id, client_id),
    CONSTRAINT ck_review_text CHECK (
        btrim(description) <> '' AND (photo_url IS NULL OR btrim(photo_url) <> '')
    ),
    CONSTRAINT ck_review_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT ck_review_order_target CHECK (entity_type <> 'заказ' OR entity_id = order_id)
);
