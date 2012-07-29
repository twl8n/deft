-- This schema supports all the different scripts.

-- create sequence "st_seq";

create table stream_flags (
	st_id integer NOT NULL auto_increment,
	is_active integer,
	reader_id varchar(255),
	out_stream integer,
	primary key (st_id)
);
-- ) TYPE=InnoDB;


create table stream_row (
	st_id_fk integer,  -- foreign key to stream_flags.st_id
	marked integer,    -- 1 is marked for read
	nd_fk integer,     -- fk to nd_key, write or read id for one operation
	data blob          -- data, real world needs to be bytea
);
-- ) TYPE=InnoDB;

create index sr_index on stream_row (st_id_fk);
create index nd_index on stream_row (nd_fk);

create table nd_keys (
	nd_pk integer NOT NULL auto_increment,
	st_id_fk integer,
	primary key (nd_pk)
);
-- ) TYPE=InnoDB;



