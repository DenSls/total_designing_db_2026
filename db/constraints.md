# Схема slastenin_food

Документ описывает типы, атрибуты, нормальные формы и ограничения схемы.
Источники требований: [ERD](../docs/erd.md), [бизнес-правила](../docs/company-rules.md),
[критерии приёмки](../docs/acceptance.md).

Схема содержит 13 таблиц: 12 сущностей ERD и нормализующую таблицу `legal_entity`.
UUID создаются через готовую `exts.uuid_generate_v4()`. Схема `exts` и расширение
`uuid-ossp` подготавливаются отдельно. FK используют `ON UPDATE NO ACTION ON DELETE NO ACTION`.

## Проектные решения

| Решение | Основание |
|---|---|
| `legal_entity` хранит ИНН и ОГРН отдельно от ресторана | Реквизиты владельца не дублируются при нескольких ресторанах, BR-4.5 |
| ФИО курьера разделено на фамилию, имя и необязательное отчество | Атомарные атрибуты, BR-6.1 |
| Расчётный счёт хранится у ресторана | BR-4.5 не задаёт один счёт на владельца и не требует истории счетов |
| Месяц зарплаты и отчёта определяется по `order_timestamp` | Единая граница месяца для процедуры выплат, генератора и представления, BR-10.2, BR-11.9 |
| Рабочие часы задаются в пределах одного дня | `work_end > work_start`; ночной интервал через полночь не моделируется, BR-4.4 |
| Адрес уникален по сохранённым `street, house_number, apartment_office` | Пробелы и регистр не нормализуются; NULL-квартира учитывается при уникальности, BR-2.5, BR-3.3 |
| `unit_price` — цена позиции на момент оформления | Изменение меню не меняет старый заказ, BR-5.2, BR-7.10 |
| `entity_type/entity_id` задают цель отзыва | Отзыв может относиться к блюду, ресторану или заказу, BR-9.1 |
| Исторические суммы и автор отзыва хранятся по контракту | Исключения нормальных форм перечислены ниже |
| Удаление родителей не каскадируется | Исторические заказы, оплаты, отзывы и выплаты сохраняются |

## ENUM-типы

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `активен`, `неактивен` | BR-4.3 |
| `product_status` | `доступно`, `нет_в_наличии`, `архив` | BR-5.5 |
| `courier_status` | `свободен`, `занят`, `на_доставке`, `уволен` | BR-6.2 |
| `order_status` | `создан`, `готовится`, `в_доставке`, `доставлен`, `отменён` | BR-7.7 |
| `order_pay_status` | `ожидает`, `оплачен`, `ошибка` | BR-7.9 |
| `payment_status` | `успех`, `ошибка`, `в_обработке` | BR-8.2 |
| `payment_type` | `карта`, `наличные`, `безнал` | BR-8.2, BR-8.6 |
| `review_entity_type` | `блюдо`, `ресторан`, `заказ` | BR-9.1 |

## Таблицы и атрибуты

Все поля обязательны, кроме помеченных `NULL`. `PK` — первичный ключ, `UQ` —
уникальное значение, `FK` — внешний ключ, `G` — вычисляемый столбец.

| Таблица | Столбцы |
|---|---|
| `client` | `client_id uuid PK`; `login varchar(50) UQ`; `password varchar(32)`; `phone_number varchar(16) UQ` |
| `address` | `address_id uuid PK`; `street varchar(150)`; `house_number varchar(20)`; `apartment_office varchar(20) NULL` |
| `client_address` | `client_id uuid PK/FK`; `address_id uuid PK/FK` |
| `legal_entity` | `legal_entity_id uuid PK`; `inn varchar(12) UQ`; `ogrn varchar(15) UQ` |
| `restaurant` | `restaurant_id uuid PK`; `restaurant_name varchar(100)`; `address_id uuid UQ/FK`; `legal_entity_id uuid FK`; `settlement_account varchar(20)`; `description varchar(500)`; `work_start time without time zone`; `work_end time without time zone`; `rating numeric(3,2) NULL`; `status restaurant_status` |
| `courier` | `courier_id uuid PK`; `last_name varchar(80)`; `first_name varchar(80)`; `middle_name varchar(80) NULL`; `phone_number varchar(16)`; `status courier_status`; `hire_date date`; `dismissal_date date NULL`; `coefficient numeric(3,2)` |
| `courier_pay` | `year integer PK`; `month smallint PK`; `courier_id uuid PK/FK`; `amount numeric(8,2)`; `coefficient_used numeric(3,2)` |
| `product_category` | `product_category_id uuid PK`; `product_category_name varchar(80)` |
| `product` | `product_id uuid PK`; `product_name varchar(100)`; `product_category_id uuid FK`; `restaurant_id uuid FK`; `price numeric(6,2)`; `description varchar(500)`; `photo_url varchar(255) NULL`; `rating numeric(3,2) NULL`; `status product_status` |
| `"order"` | `order_id uuid PK`; `client_id uuid FK`; `restaurant_id uuid FK`; `courier_id uuid FK`; `address_id uuid FK`; `order_timestamp timestamp without time zone`; `delivery_timestamp timestamp without time zone NULL`; `order_amount numeric(8,2)`; `commission numeric(8,2) G`; `total_amount numeric(8,2) G`; `status order_status`; `pay_status order_pay_status`; `description varchar(500)` |
| `order_structure` | `order_id uuid PK/FK`; `product_id uuid PK/FK`; `quantity numeric(8,3)`; `unit_price numeric(6,2)` |
| `payment` | `payment_id uuid PK`; `order_id uuid FK`; `type payment_type`; `amount numeric(8,2)`; `transaction_id varchar(100) UQ`; `transaction_timestamp timestamp without time zone`; `status payment_status` |
| `review` | `review_id uuid PK`; `order_id uuid FK`; `client_id uuid FK`; `entity_type review_entity_type`; `entity_id uuid`; `review_timestamp timestamp without time zone`; `description varchar(500)`; `photo_url varchar(255) NULL`; `rating numeric(3,2)` |

Названия, логины и адресные компоненты сравниваются как сохранены. Формат телефона
не ограничивается сверх непустой строки и длины; уникальность телефона задана только
для клиента. Фото необязательно.

## Нормальные формы

1НФ требует атомарных значений и отсутствия повторяющихся групп. В 2НФ каждый
неключевой атрибут зависит от всего каждого кандидатного ключа. Для 3НФ в каждой
нетривиальной зависимости `X → A` определитель `X` должен быть суперключом
либо зависимый атрибут `A` должен входить в кандидатный ключ.

| Таблица | Ключи и существенные зависимости | 1НФ | 2НФ | 3НФ |
|---|---|---|---|---|
| `client` | `client_id`, `login`, `phone_number` определяют строку | Да | Да | Да |
| `address` | `address_id`; сохранённая тройка уникальна | Да | Да | Да |
| `client_address` | `(client_id, address_id)` | Да | Да | Да |
| `legal_entity` | `legal_entity_id`, `inn`, `ogrn` определяют строку | Да | Да | Да |
| `restaurant` | `restaurant_id`, `address_id` определяют строку | Да | Да | Да |
| `courier` | `courier_id` определяет строку | Да | Да | Да |
| `courier_pay` | `(year, month, courier_id)` определяет сумму и применённую ставку | Да | Да | Да |
| `product_category` | `product_category_id` определяет строку | Да | Да | Да |
| `product` | `product_id` определяет строку | Да | Да | Да |
| `"order"` | `order_id`; `order_amount → commission, total_amount` | Да | Да | Нет: суммы вычисляются от неключевого атрибута |
| `order_structure` | `(order_id, product_id)` определяет количество и снимок цены | Да | Да | Да |
| `payment` | `payment_id`, `transaction_id`; `order_id → amount` по BR-8.4 | Да | Да | Нет: у заказа может быть несколько попыток |
| `review` | `review_id`, `(order_id, entity_type, entity_id)`; `order_id → client_id` | Да | Нет | Нет: автор зависит от части составного ключа |

В `"order"`, `payment` и `review` есть документированные зависимости, нарушающие
строгую 3НФ. Поля сохранены по контракту. `product.rating`, `restaurant.rating` и
`order.pay_status` определяются ключом строки и поддерживаются триггерами.
Отзыв на заказ хранится, но агрегированный рейтинг заказа не ведётся (BR-9.6/9.7).

## Ключи и связи

| Таблица | PK и дополнительные уникальные ключи | BR |
|---|---|---|
| `client` | `client_id`; `login`; `phone_number` | BR-2.2 |
| `address` | `address_id`; `(street, house_number, apartment_office)` с `NULLS NOT DISTINCT` | BR-2.5, BR-3.3 |
| `client_address` | `(client_id, address_id)` | BR-2.5 |
| `legal_entity` | `legal_entity_id`; `inn`; `ogrn` | BR-4.5 |
| `restaurant` | `restaurant_id`; `address_id` | BR-3.3 |
| `courier` | `courier_id` | BR-6.1 |
| `courier_pay` | `(year, month, courier_id)` | BR-10.3 |
| `product_category` | `product_category_id` | BR-5.7 |
| `product` | `product_id` | BR-5.1 |
| `"order"` | `order_id`; `(order_id, client_id)` для составного FK отзыва | BR-9.2 |
| `order_structure` | `(order_id, product_id)` | BR-7.16 |
| `payment` | `payment_id`; `transaction_id`; частичный UNIQUE `order_id WHERE status = 'успех'` | BR-8.1, BR-8.3 |
| `review` | `review_id`; `(order_id, entity_type, entity_id)` | BR-9.5 |

Частичный UNIQUE допускает не более одной успешной попытки оплаты на заказ.
Уникальность адресной тройки с NULL требует PostgreSQL 15 или новее.

| Дочерние столбцы | Родительские столбцы | BR |
|---|---|---|
| `client_address.client_id` | `client.client_id` | BR-2.4 |
| `client_address.address_id` | `address.address_id` | BR-2.4 |
| `restaurant.address_id` | `address.address_id` | BR-3.3 |
| `restaurant.legal_entity_id` | `legal_entity.legal_entity_id` | BR-4.5 |
| `courier_pay.courier_id` | `courier.courier_id` | BR-10.2 |
| `product.restaurant_id` | `restaurant.restaurant_id` | BR-5.1 |
| `product.product_category_id` | `product_category.product_category_id` | BR-5.1 |
| `"order".client_id` | `client.client_id` | BR-7.1 |
| `"order".restaurant_id` | `restaurant.restaurant_id` | BR-7.2 |
| `"order".courier_id` | `courier.courier_id` | BR-7.5 |
| `"order".address_id` | `address.address_id` | BR-7.4 |
| `"order".(client_id, address_id)` | `client_address(client_id, address_id)` | BR-7.4 |
| `order_structure.order_id` | `"order".order_id` | BR-7.14 |
| `order_structure.product_id` | `product.product_id` | BR-7.14 |
| `payment.order_id` | `"order".order_id` | BR-8.1 |
| `review.order_id` | `"order".order_id` | BR-9.2 |
| `review.client_id` | `client.client_id` | BR-9.2 |
| `review.(order_id, client_id)` | `"order"(order_id, client_id)` | BR-9.2 |

## CHECK, NOT NULL и NULL

Все столбцы обязательны, кроме помеченных `NULL` в словаре атрибутов.

| Таблица | Проверки | BR |
|---|---|---|
| `client` | Непустые логин и телефон; пароль — 32 строчные hex-цифры | BR-2.1–2.3 |
| `address` | Непустые улица и дом; квартира/офис либо `NULL`, либо непустые | BR-3.1–3.2 |
| `legal_entity` | Непустые ИНН и ОГРН | BR-4.5 |
| `restaurant` | Непустые название, счёт и описание; `work_end > work_start`; рейтинг 0..5 | BR-4.1–4.4 |
| `courier` | Непустые фамилия, имя и телефон; отчество либо `NULL`, либо непустое; коэффициент 0.10..0.50; дата увольнения не раньше найма; статус `уволен` требует дату | BR-6.1–6.5 |
| `courier_pay` | Год 1..9999; месяц 1..12; сумма 0..999 999.99, не `NaN`; коэффициент 0.10..0.50 | BR-10.2–10.4 |
| `product_category` | Непустое название | BR-5.7 |
| `product` | Непустые название и описание; фото либо `NULL`, либо непустое; цена ≥ 0 и не `NaN`; рейтинг 0..5 | BR-5.2–5.6 |
| `"order"` | Непустое описание; сумма ≥ 0 и не `NaN`; итог ≥ 1000; доставка не раньше создания; доставленный заказ имеет дату доставки | BR-1.8, BR-7.10–7.13 |
| `order_structure` | Количество > 0 и не `NaN`; снимок цены ≥ 0 и не `NaN` | BR-7.10, BR-7.15 |
| `payment` | Сумма ≥ 0 и не `NaN`; непустой внешний ID транзакции | BR-8.2–8.4 |
| `review` | Непустое описание; фото либо `NULL`, либо непустое; рейтинг 1..5; отзыв на заказ указывает на этот заказ | BR-9.1–9.4 |

`numeric(p,s)` исключает бесконечность, но допускает `NaN`; проверки запрещают его
для цен, сумм и количества. У URL проверяются длина и непустота, не доступность.

NULL разрешён для квартиры/офиса, отчества, даты увольнения, даты доставки, фото
и рейтингов блюда/ресторана без отзывов.

## DEFAULT и вычисляемые поля

| Таблица / поля | Значение | BR |
|---|---|---|
| Все UUID PK сущностей | `exts.uuid_generate_v4()` | BR-11.1, BR-13.3 |
| `courier.coefficient` | `0.10` | BR-6.5 |
| Временные метки заказа, платежа и отзыва | `localtimestamp` | BR-7.1, BR-8.2, BR-9.3 |
| `order.status`, `order.pay_status` | `создан`, `ожидает` | BR-7.7, BR-7.9 |
| `order.commission` | `round(order_amount * 0.10, 2)` | BR-1.4, BR-7.10 |
| `order.total_amount` | `order_amount + round(order_amount * 0.10, 2)` | BR-7.10 |

Рейтинги до появления отзывов равны `NULL` по BR-9.7. Остальные статусы и значения
задаёт вызывающий код.

## Денежные типы и расчёт

Валюта — рубли. Деньги хранятся в точном `numeric`; `real`.

| Поля | Тип | Диапазон |
|---|---|---:|
| `product.price`, `order_structure.unit_price` | `numeric(6,2)` | 0..9 999.99 |
| Сумма заказа, комиссия, итог, платёж | `numeric(8,2)` | 0..999 999.99 |
| `courier_pay.amount` | `numeric(8,2)` | 0..999 999.99 за месяц |
| `order_structure.quantity` | `numeric(8,3)` | 0.001..99 999.999 |
| Коэффициенты | `numeric(3,2)` | 0.10..0.50 |

Предел выплаты — технический выбор по BR-11.6: до 999 999.99 ₽ в месяц. Он
исключает многомиллиардную сумму; превышение диапазона вызывает переполнение и
откатывает вызов процедуры в своей транзакции.

Расчёт: `line_amount = round(quantity * unit_price, 2)`; `order_amount = sum(line_amount)`;
`commission = round(order_amount * 0.10, 2)`; `total_amount = order_amount + commission`;
`payment.amount = total_amount`; `salary = round(coefficient_used * sum(commission), 2)`.
Каждая позиция округляется до сложения, деньги хранятся до копеек.

## Межтабличные правила

`CHECK` не читает соседние строки и таблицы; межтабличные правила реализованы
триггерами в `db/schema/03_triggers.sql`. Функции ниже описаны по их назначению
в бизнес-логике.

| Правило | Реализация и логика | BR |
|---|---|---|
| T-01, T-02, T-04, T-05. Согласованность заказа | Отложенные триггеры заказа, состава, оплаты, отзыва и ресторана блюда вызывают `assert_order_change()`. Функция определяет затронутые заказы и перед фиксацией проверяет их в `assert_order_for()`: состав не пуст, сумма совпадает с позициями, блюда принадлежат ресторану, платежи и их статус согласованы, цель и автор отзыва соответствуют заказу | BR-7.3, BR-7.10, BR-7.14, BR-8.1, BR-8.4, BR-8.7, BR-9.1, BR-9.2 |
| T-03. Снимок цены позиции | `prepare_order_change()` запускается до изменений состава, оплат и отзывов. Для новой позиции берёт текущую цену блюда; изменение блюда или снимка цены существующей позиции запрещено. Для старого и нового заказа синхронизирует статус оплаты | BR-5.2, BR-7.10 |
| T-04. Статус оплаты заказа | `payment_order_status` вызывает `sync_order_pay_status()` после INSERT/UPDATE/DELETE оплаты. `order_payment_status()` возвращает «оплачен» при успешной оплате, «ожидает» при отсутствии попыток или обработке, иначе «ошибка». При переносе платежа обновляются оба заказа | BR-8.1, BR-8.4, BR-8.7 |
| T-06. Рейтинг блюда и ресторана | `review_rating_change` вызывает `rating_change()` после INSERT/UPDATE/DELETE отзыва. `refresh_review_rating()` считает среднее с округлением до двух знаков; без отзывов сохраняет NULL. При переносе отзыва обновляет рейтинг старой цели, потерявшей отзыв, и новой цели; если цель не меняется — пересчитывает её один раз. Отзыв на заказ агрегат не меняет | BR-9.6, BR-9.7 |
| T-07. История адреса заказа | `order_address_lock` и `address_history_check` вызывают `protect_order_address()`. Использованный в заказе адрес нельзя изменить; для изменения создают новый адрес. При назначении адреса заказу функция блокирует изменение адресной строки на время проверки | BR-7.4 |

Триггеры согласованности заказа отложены до конца транзакции, чтобы разрешить
создать заказ и его позиции в одной транзакции. Изменение агрегированного рейтинга
напрямую и конкурентные изменения отзывов разных заказов отдельно не защищены.

## Бизнес-функции и процедуры

| Объект | Назначение | BR |
|---|---|---|
| `add_product()` | Добавляет блюдо; до появления отзывов его рейтинг должен быть NULL | BR-5.1–5.6 |
| `insert_test_data(value)` | Создаёт согласованный набор тестовых данных для проверки схемы и бизнес-правил | BR-11.7 |
| `erase_test_data()` | Удаляет созданные данные, сохраняя типы, функции и структуру схемы | — |
| `get_statistic()` | Для каждого ресторана возвращает выручку и средний чек по доставленным заказам, самое продаваемое блюдо и клиента с наибольшим числом доставленных заказов | BR-11.8 |
| `courier_salary()` | Рассчитывает выплаты курьерам за текущий месяц по комиссиям доставленных заказов и сохранённому коэффициенту; затем назначает коэффициент для следующего расчёта по числу доставок | BR-10.1–10.6 |
| `how_much_money` | Представление помесячно показывает суммы заказов, комиссию, выплаты курьерам и разницу комиссии с выплатами | BR-11.9 |
