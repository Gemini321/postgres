%option noyywrap nodefault
%option prefix="c_parser_"

%{
#include "postgres_fe.h"

#include "c_parser.h"
#include "c_parser.tab.h"
%}

IDENT [A-Za-z_][A-Za-z0-9_]*
NUMBER [0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?
STRING \"([^\"\\\n]|\\.)*\"
WS [ \t\r\n]+

%%

{WS}              ;
"int"             { return CDECL_INT; }
"char"            { return CDECL_CHAR; }
"float"           { return CDECL_FLOAT; }
"double"          { return CDECL_DOUBLE; }
"long"            { return CDECL_LONG; }
"unsigned"        { return CDECL_UNSIGNED; }
"bool"            { return CDECL_BOOL; }
"struct"          { return CDECL_STRUCT; }
"union"           { return CDECL_UNION; }
"enum"            { return CDECL_ENUM; }
"void"            { return CDECL_VOID; }
"for"             { return CDECL_FOR; }
"if"              { return CDECL_IF; }
"else"            { return CDECL_ELSE; }
"typedef"         { return CDECL_TYPEDEF; }
"const"           { return CDECL_CONST; }
"volatile"        { return CDECL_VOLATILE; }
{IDENT}            {
						if (ecpg_c_parser_is_typedef_name(yytext))
						{
							c_parser_lval.str = mm_strdup(yytext);
							return CDECL_TYPE_NAME;
						}
						c_parser_lval.str = mm_strdup(yytext);
						return CDECL_IDENTIFIER;
					}
{NUMBER}           { c_parser_lval.str = mm_strdup(yytext); return CDECL_NUMBER; }
{STRING}           { c_parser_lval.str = mm_strdup(yytext); return CDECL_STRING; }
";"               { return ';'; }
"["               { return '['; }
"]"               { return ']'; }
"*"               { return '*'; }
"="               { return '='; }
","               { return ','; }
.                  { return yytext[0]; }

%%
