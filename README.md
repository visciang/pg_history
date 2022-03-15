# Postgres table history (via trigger)

Track the historical series of changes of a table.

Given a table with an "id" primary key column, you can track row level changes with:

```
call history.add('public', 'salary');
```

The changes are stored in a distinct table under `history.t_`.
This table tracks every change in terms of:
- `op`: the operation that changed the row (INSERT, UPDATE, ...)
- `row_id`: the `id` of the changed row in the source table
- `row`: jsonb representation of the record (post change)
- `at`: when the change occurred
- `id`: sequence number sorting the changes

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
 id |    op    |                row_id                |                                          row                                           |              at               
----+----------+--------------------------------------+----------------------------------------------------------------------------------------+-------------------------------
  1 | INSERT   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 22, "employee": "John Black"} | 2022-03-15 19:32:39.357983+00
  2 | INSERT   | 17517fbe-d33f-457a-bb82-4aa1212c7b08 | {"id": "17517fbe-d33f-457a-bb82-4aa1212c7b08", "amount": 25, "employee": "Jane White"} | 2022-03-15 19:32:57.018437+00
  3 | UPDATE   | 17517fbe-d33f-457a-bb82-4aa1212c7b08 | {"id": "17517fbe-d33f-457a-bb82-4aa1212c7b08", "amount": 30, "employee": "Jane White"} | 2022-03-15 19:33:04.145736+00
  4 | UPDATE   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 24, "employee": "John Black"} | 2022-03-15 19:33:20.323789+00
  5 | UPDATE   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 27, "employee": "John Black"} | 2022-03-15 19:33:21.026718+00
  6 | DELETE   | 4f23d344-aad9-4012-8570-2c613e0aed2a |                                                                                        | 2022-03-15 19:33:32.225305+00
  7 | TRUNCATE |                                      |                                                                                        | 2022-03-15 19:33:43.187489+00
(7 rows)

# Salary history of 'John Black'

postgres=# select * from history.t_1 where row_id = '4f23d344-aad9-4012-8570-2c613e0aed2a' or row_id is null order by id;
 id |    op    |                row_id                |                                          row                                           |              at               
----+----------+--------------------------------------+----------------------------------------------------------------------------------------+-------------------------------
  1 | INSERT   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 22, "employee": "John Black"} | 2022-03-15 19:32:39.357983+00
  4 | UPDATE   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 24, "employee": "John Black"} | 2022-03-15 19:33:20.323789+00
  5 | UPDATE   | 4f23d344-aad9-4012-8570-2c613e0aed2a | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 27, "employee": "John Black"} | 2022-03-15 19:33:21.026718+00
  6 | DELETE   | 4f23d344-aad9-4012-8570-2c613e0aed2a |                                                                                        | 2022-03-15 19:33:32.225305+00
  7 | TRUNCATE |                                      |                                                                                        | 2022-03-15 19:33:43.187489+00
(5 rows)

postgres=# select id, op, history.jsonb_diff(lag(row) over (order by id), row) diff from history.t_1 where row_id = '4f23d344-aad9-4012-8570-2c613e0aed2a' or row_id is null order by id;
 id |    op    |                                          diff                                          
----+----------+----------------------------------------------------------------------------------------
  1 | INSERT   | {"id": "4f23d344-aad9-4012-8570-2c613e0aed2a", "amount": 22, "employee": "John Black"}
  4 | UPDATE   | {"amount": 24}
  5 | UPDATE   | {"amount": 27}
  6 | DELETE   | {"id": null, "amount": null, "employee": null}
  7 | TRUNCATE | 
(5 rows)
```

Remove history

```
postgres=# call history.remove('public', 'salary');
NOTICE:  dropped history.t_1 table
```
