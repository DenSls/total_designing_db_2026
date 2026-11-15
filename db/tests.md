# Проверка FoodExpress

Дата последних проверок: 2026-11-15. Среда: PostgreSQL 17.11;
рабочая служба пользователя не менялась.

## Чистая установка

Схема `exts` и расширение `uuid-ossp` должны быть созданы до установки проекта,
как требует BR-13.3.

    createdb foodexpress_test
    psql -X -v ON_ERROR_STOP=1 -d foodexpress_test \
      -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" WITH SCHEMA exts;'

От владельца объектов применить SQL-файлы по порядку:

    for f in db/schema/01_types.sql db/schema/02_tables.sql \
             db/schema/03_triggers.sql db/schema/04_business_routines.sql \
             db/schema/05_test_data.sql db/schema/grants.sql; do
      psql -X -v ON_ERROR_STOP=1 -d foodexpress_test -f "$f" || exit 1
    done

Схема и grants устанавливаются от владельца с правом управления ролями.
Функциональные проверки FOOD-109 выполняются отдельным подключением `inspector`.

## Фактические результаты

| Этап | Проверено | Результат |
|---|---|---|
| FOOD-101.1/101.2 | Чистая установка, 13 объектов, 12 таблиц, 8 ENUM, ключи и связи | PASS |
| FOOD-101.3 | Состав заказа, ресторан блюд, суммы, снимки цен, оплаты, отзывы, адрес и обратные изменения | PASS |
| FOOD-102 | Количества, связи, даты, суммы, выплаты, рейтинги, ENUM и пределы varchar | PASS |
| FOOD-103/104 | Очистка, повторная генерация, добавление блюда, проверки FK, CHECK, NULL и границ аргументов | PASS |
| FOOD-105 | INSERT/UPDATE/DELETE, смена оценки/типа/цели, массовые изменения, AVG, округление, NULL и откат | PASS |
| FOOD-106–108 | Статистика, пороги коэффициента, повторное начисление, уволенные и денежный отчёт | PASS |
| FOOD-109 | Подключение `inspector`, права на объекты и каталоги, обязательные вызовы | PASS |
| FOOD-110 | Custom-архив, восстановление в чистую БД, совпадение DDL и приёмка под `inspector` | PASS |


### Денежный предел выплаты

После изменения `courier_pay.amount` на `numeric(8,2)` установлены файлы
`01_types.sql`–`05_test_data.sql` на чистую БД. Выполнен `insert_test_data(10)`,
затем `courier_salary()`. Созданы 60 строк выплат.

Проверки типа прошли: 999 999.99 ₽ принимается; 1 000 000.00 ₽ вызывает переполнение;
`NaN` и бесконечность отклоняются; значение 1.234 ₽ сохраняется как 1.23 ₽.

## FOOD-110: резервная копия и восстановление

Архив `db/foodexpress_slastenin.backup` создан на PostgreSQL 17.11: 71 242 байта,
90 записей оглавления. Он содержит только DDL схемы `slastenin_food`, без данных
и ACL. С `--no-owner` объекты принадлежат роли, выполняющей восстановление;
роль `inspector` и права создаёт `grants.sql`. Схема `exts` подготавливается отдельно.

Создать custom archive и проверить его оглавление:

    pg_dump -Fc --schema-only --no-acl --no-owner -n slastenin_food \
      -f db/foodexpress_slastenin.backup foodexpress
    pg_restore --list db/foodexpress_slastenin.backup

Создать чистую БД, подготовить `exts` с `uuid-ossp`, затем восстановить архив:

    createdb foodexpress_restore
    psql -X -v ON_ERROR_STOP=1 -d foodexpress_restore \
      -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" WITH SCHEMA exts;'
    pg_restore --no-owner --no-acl --exit-on-error --single-transaction -d foodexpress_restore \
      db/foodexpress_slastenin.backup
    psql -X -v ON_ERROR_STOP=1 -d foodexpress_restore -f db/schema/grants.sql

Восстановление в новом временном кластере прошло без ошибок; DDL совпал
с исходной схемой. `grants.sql` создал отсутствовавшую роль `inspector` без
административных прав; проверен вход по паролю.

Два вызова `insert_test_data(10)` создали 100 заказов; независимые запросы
подтвердили количества строк, суммы, рестораны, оплаты, рейтинги и выплаты.
Выполнены `add_product`, `get_statistic`, два `courier_salary`, чтение
`how_much_money`, двойная очистка и новая генерация.
