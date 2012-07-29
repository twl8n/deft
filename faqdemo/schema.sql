
create sequence "pk_seq";
	
create table faq (
	"faq_pk" integer DEFAULT nextval('pk_seq'::text) NOT NULL,
	"question" text,
	"answer"    text,
	"keywords" text,
	"valid" integer
) without oids;
	
REVOKE ALL on "faq" from PUBLIC;
GRANT ALL on "faq" to "faqdemo";


