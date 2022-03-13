create schema history;

create type history.op as enum ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');

create table history.tables (
    id bigint generated always as identity,
    table_schema text not null,
    table_name text not null,

    primary key (table_schema, table_name)
);

create procedure history.add(table_schema_ text, table_name_ text) language plpgsql as $$
declare
    table_id bigint;
    row_id_type text;
begin
    if not exists (
        select true from information_schema.columns
        where table_schema = table_schema_ and table_name = table_name_ and column_name = 'id') then
        raise 'table %.% should have an "id" (PK) column', table_schema_, table_name_;
    end if;

    select data_type into row_id_type
    from information_schema.columns
    where table_schema = table_schema_ and table_name = table_name_;

    insert into history.tables (table_schema, table_name) values (table_schema_, table_name_)
    returning id into table_id;

    execute format('
        create table history.t_%s (
            id bigint generated always as identity,
            row_id %s,
            op history.op not null,
            old jsonb,
            new jsonb,
            at timestamp with time zone default now(),

            primary key (id)
        )
    ', table_id, row_id_type);

    execute format('
        create index on history.t_%s (row_id)
    ', table_id);

    execute format('
        create trigger h_iud_%s
        after insert or update or delete on %I.%I
        for each row execute function history.trigger()
    ', table_id, table_schema_, table_name_);

    execute format('
        create trigger h_t_%s
        after truncate on %I.%I
        for each statement execute function history.trigger()
    ', table_id, table_schema_, table_name_);

    raise notice 'created history.t_% table', table_id;
end $$;

create procedure history.remove(table_schema_ text, table_name_ text) language plpgsql as $$
declare
    table_id bigint;
begin
    delete from history.tables
    where table_schema = table_schema_ and table_name = table_name_
    returning id into table_id;

    execute format('
        drop table history.t_%s
    ', table_id);

    execute format('
        drop trigger h_iud_%s on %I.%I
    ', table_id, table_schema_, table_name_);

    execute format('
        drop trigger h_t_%s on %I.%I
    ', table_id, table_schema_, table_name_);

    raise notice 'dropped history.t_% table', table_id;
end $$;

create function history.trigger() returns trigger language plpgsql as $$
declare
    table_id bigint;
begin
    select id into table_id
    from history.tables
    where table_schema = TG_TABLE_SCHEMA and table_name = TG_TABLE_NAME;

    if (TG_OP = 'TRUNCATE') then
        execute format('
            insert into history.t_%s (row_id, op, old, new) values (%L, %L, %L, %L)
        ', table_id, null, TG_OP, null, null);
    elsif (TG_OP = 'INSERT') then
        execute format('
            insert into history.t_%s (row_id, op, old, new) values (%L, %L, %L, %L)
        ', table_id, NEW.id, TG_OP, null, to_jsonb(NEW));
    elsif (TG_OP = 'DELETE') then
        execute format('
            insert into history.t_%s (row_id, op, old, new) values (%L, %L, %L, %L)
        ', table_id, OLD.id, TG_OP, to_jsonb(OLD), null);
    elsif (TG_OP = 'UPDATE') then
        if NEW is distinct from OLD then
            execute format('
                insert into history.t_%s (row_id, op, old, new) values (%L, %L, %L, %L)
            ', table_id, OLD.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        end if;
    end if;

    return null;
end $$;
