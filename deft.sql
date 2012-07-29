create sequence "pk_seq";
create sequence "st_seq";    -- used by stream_row
create sequence "graph_seq"; -- used by graph
create sequence "node_seq";  -- used by node
create sequence "ec_seq";    -- used by edge 
create sequence "code_seq";  -- used by code 

-- insert into config (name,value) values ("hosts", "zeus");
-- insert into config (name,value) values ("hosts", "athena");

create table config (
	name varchar(128),
	value varchar(256)
) without oids;

--
-- User databases we know about.
-- Tables must be here before we can use do_sql_simple().
--
create table "deft_tables" (
	tab_pk integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	db_alias varchar(256) unique,
	db_name varchar(256),
	dbms varchar(128),
	db_host varchar(128),
	db_port varchar(32),
	db_user varchar(32),
	db_password varchar(128),
	du_fk integer -- foreign key to deft_users.du_pk
) without oids;

-- Multihost tcp and dbq stream table: family
-- Not used by version.
-- (field removed) subroutines text,	-- subs for this line of Deft
create table "family" (
	fid varchar(128), 	-- family id
	out_stream integer,
	in_stream integer,
	active_flag integer default 1,
	code text		-- one line of Deft
) without oids;

create table dbq_code (
	code_id integer DEFAULT nextval('st_seq'::text) NOT NULL,
	fcode bytea		-- frozen hash of lists.
) without oids;

-- Database queue tables: dbq_flags dbq_row
-- Not used by st or tcp versions.
create table dbq_flags (
	sf_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
	family integer,	
	is_active integer,
	reader_id varchar(256),
	sf_in integer,
	sf_out integer,
	code text
) without oids;

-- Row(s) of data. Used by tcp version only
-- for the initial stream to the top ancestor.
create table stream_row (
	st_id_fk integer,	-- input stream
	marked integer,		-- 1 is marked for read
	data bytea		-- data, real world needs to be bytea
) without oids;

-- Row(s) of data. Used by dbq version
create table dbq_row (
	dr_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
	sr_in integer,		-- sort of a foreign key to dbq_flags.sf_in
	marked integer,		-- 1 is marked for read
	data bytea		-- data, real world needs to be bytea
) without oids;

create index sr_index on dbq_row (sr_in);


--
-- Everything from here down is related to the state machine.
-- 

-- Graphs are owed by these users (which are also unix logins)
-- Other records are owned by a graph and are therefore indirectly
-- owned by a user.

create table "deft_users" (
	du_pk integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	logname varchar(128)
) without oids;

create unique index du_pk_logname_index on deft_users (du_pk,logname);



--
-- Compiled runt templates.
-- dec 09 2005 change comment for te_date
-- change te_name to text so there's no size limit

create table "template" (
	te_pk integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	te_name text,                     -- full path. was template name w/o extension (aka stem)
	te_date timestamp with time zone, -- original file timestamp
	te_code bytea                     -- the compiled version of the template
) without oids;

--
-- Graph is the tree of nodes that comprise the states of the state machine.
-- Graphs are owned by users. Graph names must be unique per user.
-- 

create table "graph" (
	gr_pk integer DEFAULT nextval('graph_seq'::text) NOT NULL,
	graph_name varchar(128),
	gr_date timestamp with time zone,
	gr_path varchar(256),
	du_fk varchar(128) not null        -- deft_users.du_fk
) without oids;

create unique index graph_name_du_fk on graph (graph_name,du_fk);

--
-- node aka state
-- Nodes are used, but only as labels. Code executes only as part of an edge.
--

create table "node" (
	node_pk integer DEFAULT nextval('node_seq'::text) NOT NULL,
	gr_fk integer,           -- graph fk
	node_name varchar(128)    -- name or label of this node
) without oids;

create table "edge" (
	ec_pk integer DEFAULT nextval('ec_seq'::text) NOT NULL,
	edge_order integer,
	code_fk integer,
	gr_fk integer,
	is_var integer default 0,   -- boolean, is this edge a variable instead of code
	code_var_name varchar(128), -- code or  variable name
	invert integer default 0,   -- boolean, invert the return value of this edge
	from_node_fk integer,       -- current state label
	to_node_fk integer,         -- transition this label if var/action is true
	is_wait integer default 0   -- boolean, wait before transition.
) without oids;

--
-- Code is owned by a graph. Code nams must be unique per graph.
-- 

create table code (
	code_pk integer DEFAULT nextval('code_seq'::text) NOT NULL,
	code_date timestamp with time zone,
	code_name varchar(128), -- name of this deft script
	gr_fk integer,          -- foreign key to graph.gr_pk
	source text             -- the code
) without oids;

create unique index code_name_gr_fk on code (code_name, gr_fk);

