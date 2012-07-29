-- database bug_pages

create sequence "pk_seq" start 1 increment 1 maxvalue 2147483647 minvalue 1 cache 1;

create table bug_sites (
	"sequence" integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	"url"      varchar(256),
	"title"    text,
	"description" text,
	"keywords" text
) without oids;
	
REVOKE ALL on "bug_sites" from PUBLIC;
GRANT ALL on "bug_sites" to "bug_pages";

create table bug_faq (
	"bf_pk" integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	"question" text,
	"answer"    text,
	"keywords" text
) without oids;
	
REVOKE ALL on "bug_faq" from PUBLIC;
GRANT ALL on "bug_faq" to "bug_pages";


