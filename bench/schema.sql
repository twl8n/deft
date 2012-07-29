-- This schema supports all the different scripts.

create sequence "st_seq";

create table stream_flags (
	sf_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
	is_active integer,
	reader_id varchar(256),
	sf_in integer,
	sf_out integer
) without oids;


create table stream_row (
	sr_in integer,		-- foreign key to stream_flags.st_id
	marked integer,		-- 1 is marked for read
	nd_fk integer,          -- fk to nd_key, write or read id for one operation
	data bytea		-- data, real world needs to be bytea
) without oids;

create index sr_index on stream_row (sr_in);
create index nd_index on stream_row (nd_fk);

create table nd_keys (
	nd_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
	st_id_fk integer
) without oids;



