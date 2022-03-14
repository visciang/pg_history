# Postgres table history (via trigger)

Track the historical series of changes of a table.

Given a table with an "id" primary key column, you can track row level changes with:

```
call history.add('public', 'salary');
```

The changes are stored in a distinct table under `history.t_`.
This table tracks every change in terms of:
- `row_id`: the `id` of the changed row in the source table/
- `op`: the operation that changed the row (INSERT, UPDATE, ...)
- `old`: jsonb representation of the old record (pre change)
- `new`: jsonb representation of the new record (post change)
- `at`: when the change occurred
- `id`: sequence number to sort the changes

## Usage example

Setup sample table:

```
$ psql -U postgres

postgres=# \i history.sql

postgres=# create table salary(
  id uuid default gen_random_uuid() primary key,  -- mandatory field `id`
  employee text not null,
  amount int
);

postgres=# create unique index on salary (employee);

postgres=# call history.add('public', 'salary');
NOTICE:  created history.t_1 table

postgres=# select * from history.tables;
 id | table_schema | table_name
----+--------------+------------
  1 | public       | salary
(1 row)
```

Load data:

```
postgres=# insert into salary (employee, amount) values ('John Black', 22);
postgres=# insert into salary (employee, amount) values ('Jane White', 25);
postgres=# update salary set amount=30 where employee='Jane White';
postgres=# update salary set amount=24 where employee='John Black';
postgres=# update salary set amount=27 where employee='John Black';
postgres=# delete from salary where employee='John Black';
postgres=# truncate salary;
```

Query history:

```
# full table history

postgres=# select * from history.t_1 order by id;
 id |                row_id                |    op    |                                          old                                           |                                          new                                           |              at
----+--------------------------------------+----------+----------------------------------------------------------------------------------------+----------------------------------------------------------------------------------------+-------------------------------
  1 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | INSERT   |                                                                                        | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 22, "employee": "John Black"} | 2022-03-14 11:36:00.840134+00
  2 | 939a3b59-e10d-426f-95ce-4e6eed2c5f82 | INSERT   |                                                                                        | {"id": "939a3b59-e10d-426f-95ce-4e6eed2c5f82", "amount": 25, "employee": "Jane White"} | 2022-03-14 11:36:28.319889+00
  3 | 939a3b59-e10d-426f-95ce-4e6eed2c5f82 | UPDATE   | {"id": "939a3b59-e10d-426f-95ce-4e6eed2c5f82", "amount": 25, "employee": "Jane White"} | {"id": "939a3b59-e10d-426f-95ce-4e6eed2c5f82", "amount": 30, "employee": "Jane White"} | 2022-03-14 11:36:57.814848+00
  4 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | UPDATE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 22, "employee": "John Black"} | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 24, "employee": "John Black"} | 2022-03-14 11:36:57.835685+00
  5 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | UPDATE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 24, "employee": "John Black"} | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 27, "employee": "John Black"} | 2022-03-14 11:36:59.22395+00
  6 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | DELETE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 27, "employee": "John Black"} |                                                                                        | 2022-03-14 11:37:45.743582+00
  7 |                                      | TRUNCATE |                                                                                        |                                                                                        | 2022-03-14 11:37:52.520035+00
(7 rows)

# Salary history of 'John Black'

postgres=# select * from history.t_1 where row_id = '93ae5bcb-23d1-4ed4-bb41-87199f7174e6' or row_id is null order by id;
 id |                row_id                |    op    |                                          old                                           |                                          new                                           |              at
----+--------------------------------------+----------+----------------------------------------------------------------------------------------+----------------------------------------------------------------------------------------+-------------------------------
  1 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | INSERT   |                                                                                        | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 22, "employee": "John Black"} | 2022-03-14 11:36:00.840134+00
  4 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | UPDATE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 22, "employee": "John Black"} | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 24, "employee": "John Black"} | 2022-03-14 11:36:57.835685+00
  5 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | UPDATE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 24, "employee": "John Black"} | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 27, "employee": "John Black"} | 2022-03-14 11:36:59.22395+00
  6 | 93ae5bcb-23d1-4ed4-bb41-87199f7174e6 | DELETE   | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 27, "employee": "John Black"} |                                                                                        | 2022-03-14 11:37:45.743582+00
  7 |                                      | TRUNCATE |                                                                                        |                                                                                        | 2022-03-14 11:37:52.520035+00
(5 rows)

postgres=# select id, history.jsonb_diff(old, new) from history.t_1 where row_id = '93ae5bcb-23d1-4ed4-bb41-87199f7174e6' or row_id is null order by id;
 id |                                       jsonb_diff
----+----------------------------------------------------------------------------------------
  1 | {"id": "93ae5bcb-23d1-4ed4-bb41-87199f7174e6", "amount": 22, "employee": "John Black"}
  4 | {"amount": 24}
  5 | {"amount": 27}
  6 | {"id": null, "amount": null, "employee": null}
  7 |
(5 rows)
```

Remove history

```
postgres=# call history.remove('public', 'salary');
NOTICE:  dropped history.t_1 table
```
