CREATE SCHEMA slastenin_food;

CREATE TYPE slastenin_food.restaurant_status AS ENUM ('активен', 'неактивен');
CREATE TYPE slastenin_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');
CREATE TYPE slastenin_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE slastenin_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE slastenin_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE slastenin_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');
CREATE TYPE slastenin_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');
CREATE TYPE slastenin_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');
