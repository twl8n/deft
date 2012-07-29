
--
-- Used for the st_pk of the stream tables.
-- Use defaults when creating sequences. The defaults are good.
-- 
--create sequence "st_seq";

DROP TABLE IF EXISTS st_seq;
CREATE TABLE `st_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO st_seq SET id=0;

-- create sequence "fa_seq";

-- Need family id fid field and sequence?
DROP TABLE IF EXISTS family;
create table `family` (
	-- fa_pk integer DEFAULT nextval('fa_seq'::text) NOT NULL,
	out_stream int,
	out_stream_name varchar(128),
	in_stream int,
	active_flag int default 1,
	code text
);
--) without oids;

--
-- An idea for a relational model for streams.
-- Seems to require 3 tables.
-- 
--create table "stream_row" (
--	sr_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
--	out_stream_fk integer,  -- foreign key to family.our_stream
--	sr_ok boolean default 't'
--) without oids;

--sr_fk integer,          -- foreign key to stream_row.sr_pk
DROP TABLE IF EXISTS stream_column;
create table `stream_column` (
	out_stream_fk int,
	os_row varchar(128),
	col_name varchar(128),
	col_value blob
);
--) without oids;
create index osr_index on stream_column (os_row);

--
-- An idea for freezing $::eenv{data} like before
-- so that the stream table only needs one data column.
-- 
--create table stream (
--	st_pk integer DEFAULT nextval('st_seq'::text) NOT NULL,
--	st_ok boolean default 't',
--	st_data bytea
--) without oids;



--create sequence "pk_seq";
DROP TABLE IF EXISTS pk_seq;
CREATE TABLE `pk_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO pk_seq SET id=0;
--
-- User tables we know about.
-- Tables must be here before we can use do_sql_simple().
--
DROP TABLE IF EXISTS deft_tables;
create table `deft_tables` (
	tab_pk integer NOT NULL auto_increment,
	db_canonical_name varchar(255) NOT NULL default '',
	db_name varchar(255),
	dbms varchar(128),
	db_host varchar(128),
	db_port varchar(32),
	db_user varchar(32),
	db_password varchar(128),
  PRIMARY KEY `tab_pk` (`tab_pk`),
  UNIQUE KEY `db_canonical_name` (`db_canonical_name`)
);
--) without oids;

DROP TABLE IF EXISTS template;
create table `template` (
	te_pk integer NOT NULL auto_increment,
	te_name varchar(128),             
	te_date timestamp, 
	te_code blob,                    
  PRIMARY KEY `te_pk` (`te_pk`)
);
--) without oids;

--
-- machine is the Perl code that is the state machine
-- e.g. the universal machine.
-- see machine.pl 
--
-- graph is the tree of nodes that comprise the states of the state machine.
-- 
--create sequence "graph_seq";
DROP TABLE IF EXISTS graph_seq;
CREATE TABLE `graph_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO graph_seq SET id=0;

DROP TABLE IF EXISTS graph;
create table `graph` (
	gr_pk integer NOT NULL auto_increment,
	graph_name varchar(128),
	gr_date timestamp ,
  PRIMARY KEY `gr_pk` (`gr_pk`)
);
--) without oids;


--
-- node aka state
-- Nodes are only labels. Code executes only as part of an edge.
-- code_fk integer          -- which code to execute now
--
--create sequence "node_seq";
DROP TABLE IF EXISTS node_seq;
CREATE TABLE `node_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO node_seq SET id=0;

DROP TABLE IF EXISTS node;
create table `node` (
	node_pk integer NOT NULL auto_increment,
	gr_fk integer,           -- graph fk
	node_name varchar(128),    -- name or label of this node
  PRIMARY KEY `node_pk` (`node_pk`)
);
--) without oids;

--create sequence "ec_seq";
DROP TABLE IF EXISTS ec_seq;
CREATE TABLE `ec_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO ec_seq SET id=0;

DROP TABLE IF EXISTS edge;
create table `edge` (
	ec_pk integer NOT NULL auto_increment,
	edge_order integer,
	code_fk integer,
	is_var integer,        -- boolean, is this edge a variable instead of code
	var_name varchar(128), -- edge variable name
	invert integer,        -- boolean, invert the return value of this edge
	from_node_fk integer,  -- I'm an edge of this fk to node.node_pk
	to_node_fk integer,    -- I transition to this fk to node.node_pk
	is_wait integer,        -- boolean, wait before transition to next node.
  PRIMARY KEY `ec_pk` (`ec_pk`)
);
--) without oids;


--create sequence "code_seq";
DROP TABLE IF EXISTS code_seq;
CREATE TABLE `code_seq` ( `id` INT NOT NULL AUTO_INCREMENT , PRIMARY KEY ( `id` ));
INSERT INTO code_seq SET id=0;

--
-- I think is_state was intended to distinguish test code from
-- action code. Probably not meaningful.
-- 

DROP TABLE IF EXISTS code;
create table code (
	code_pk integer NOT NULL auto_increment,
  PRIMARY KEY `code_pk` (`code_pk`),
	code_name varchar(128), 
	is_state integer,       -- interger instead of boolean avoids type conversion headaches.
	code_date timestamp,
	source text             
);
--) without oids;


