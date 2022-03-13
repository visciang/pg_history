# Postgres table history (via trigger)

Load history "extension":

```
$ psql -U postgres -f history.sql
```

Test history:

```
$ psql -U postgres

postgres=# create table tab(
  id int primary key,
  field text
);

postgres=# call history.add('public', 'tab');
NOTICE:  created history.t_1 table

postgres=# select * from history.tables;
 id | table_schema | table_name 
----+--------------+------------
  1 | public       | tab
(1 row)

postgres=# insert into tab values (90, 'a');
postgres=# insert into tab values (91, 'b');
postgres=# update tab set field='bb' where id=91;
postgres=# delete from tab where id=90;
postgres=# truncate tab;

postgres=# select * from history.t_1;
 id | row_id |    op    |           old            |            new            |              at               
----+--------+----------+--------------------------+---------------------------+-------------------------------
  3 |     90 | INSERT   |                          | {"id": 90, "field": "a"}  | 2022-03-13 21:37:17.016834+00
  4 |     91 | INSERT   |                          | {"id": 91, "field": "b"}  | 2022-03-13 21:37:22.038198+00
  5 |     91 | UPDATE   | {"id": 91, "field": "b"} | {"id": 91, "field": "bb"} | 2022-03-13 21:37:36.258119+00
  6 |     90 | DELETE   | {"id": 90, "field": "a"} |                           | 2022-03-13 21:37:43.60254+00
  7 |        | TRUNCATE |                          |                           | 2022-03-13 21:37:47.524263+00
(5 rows)
```
