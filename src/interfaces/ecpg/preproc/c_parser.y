%{
#include "postgres_fe.h"

#include "preproc_extern.h"
#include "c_parser.h"

int c_parser_lex(void);
void c_parser_error(const char *msg);

struct CDeclNameList
{
	char			   *name;
	int					pointer_level;
	struct array_dim   *array_dims;
	struct CDeclNameList *next;
};

struct CParamDecl
{
	CDeclType	type;
	CDeclNameList *name;
	struct CParamDecl *next;
};

static void register_simple_declaration_at_level(const CDeclType *type, const CDeclNameList *name, int level);
static void register_name_list(const CDeclType *type, CDeclNameList *list);
static void register_name_list_at_level(const CDeclType *type, CDeclNameList *list, int level);
static CDeclNameList *make_name_node(char *name, int pointer_level, struct array_dim *array_dims);
static CDeclNameList *append_name_node(CDeclNameList *list, CDeclNameList *tail);
static void free_name_list(CDeclNameList *list);
static struct ECPGtype *build_simple_type(const CDeclType *type, const CDeclNameList *name);
static struct array_dim *c_parser_make_array_dim(char *size);
static struct array_dim *c_parser_append_array_dim(struct array_dim *list, struct array_dim *dim);
static void c_parser_free_array_dims(struct array_dim *list);
static struct ECPGtype *apply_array_dims(struct ECPGtype *type, struct array_dim *dims);
static void c_parser_register_struct_def(const char *name, struct ECPGstruct_member *members);
static void c_parser_register_union_def(const char *name, struct ECPGstruct_member *members);
static struct ECPGstruct_member *c_parser_lookup_struct_def(const char *name);
static struct ECPGstruct_member *c_parser_lookup_union_def(const char *name);
static char *c_parser_make_anon_struct_name(void);
static char *c_parser_make_anon_union_name(void);
static struct ECPGstruct_member *c_parser_build_struct_members(const CDeclType *type, CDeclNameList *names);
static struct ECPGstruct_member *c_parser_append_struct_members(struct ECPGstruct_member *list, struct ECPGstruct_member *tail);
static bool c_parser_is_char_pointer(enum ECPGttype type);
static void register_typedef_declaration(const CDeclType *type, CDeclNameList *list);
static void c_parser_add_typedef(const char *name, struct ECPGtype *type);
static struct ECPGtype *c_parser_dup_type(const struct ECPGtype *type);
static struct CTypedef *c_parser_lookup_typedef_entry(const char *name);
static void register_parameter_list(CParamDecl *params);
static CParamDecl *c_parser_make_param(CDeclType *type, CDeclNameList *name);
static CParamDecl *c_parser_append_param(CParamDecl *list, CParamDecl *tail);
static void c_parser_free_param_list(CParamDecl *list);
static bool ecpg_c_parser_matched_flag = false;
static int ecpg_c_parser_current_brace_level = 0;
typedef struct CStructDef
{
	char			   *name;
	struct ECPGstruct_member *members;
	struct CStructDef *next;
} CStructDef;

static CStructDef *c_parser_struct_defs = NULL;
static int	c_parser_anon_struct_id = 0;

typedef struct CUnionDef
{
	char			   *name;
	struct ECPGstruct_member *members;
	struct CUnionDef *next;
} CUnionDef;

static CUnionDef *c_parser_union_defs = NULL;
static int	c_parser_anon_union_id = 0;

typedef struct CTypedef
{
	char			   *name;
	struct ECPGtype *type;
	int					brace_level;
	struct CTypedef   *next;
} CTypedef;

static CTypedef *c_parser_typedefs = NULL;

void
ecpg_c_parser_set_brace_level(int level)
{
	ecpg_c_parser_current_brace_level = level;
}

bool
ecpg_c_parser_matched_declaration(void)
{
	return ecpg_c_parser_matched_flag;
}

void
ecpg_c_parser_reset_match(void)
{
	ecpg_c_parser_matched_flag = false;
}
%}

%define api.prefix {c_parser_}
%define parse.error verbose

%union
{
	char *str;
	CDeclType decl_type;
	CDeclNameList *decl_list;
	struct array_dim *array_dims;
	struct ECPGstruct_member *struct_members;
	int		ival;
	CParamDecl *param_list;
}

%token CDECL_INT CDECL_CHAR CDECL_FLOAT CDECL_DOUBLE
%token CDECL_LONG CDECL_UNSIGNED CDECL_BOOL CDECL_VOID
%token CDECL_STRUCT CDECL_UNION CDECL_ENUM CDECL_TYPEDEF
%token CDECL_FOR CDECL_IF CDECL_ELSE
%token CDECL_CONST CDECL_VOLATILE
%token <str> CDECL_IDENTIFIER
%token <str> CDECL_NUMBER
%token <str> CDECL_STRING
%token <str> CDECL_TYPE_NAME

%type <decl_type> simple_type qualified_type struct_specifier union_specifier enum_specifier
%type <decl_list> declarator declarator_list init_declarator init_declarator_list function_pointer_parameter
%type <ival> pointer_opt pointer_seq
%type <array_dims> array_opt array_dims
%type <ival> type_qualifier_seq type_qualifier
%type <struct_members> struct_body struct_field_list struct_field_declaration
%type <ival> initializer_opt initializer initializer_list designation designator_list designator assignment_expression assignment_primary opt_assignment_expression enumerator_list enumerator abstract_parameter_list abstract_parameter_list_nonempty abstract_parameter_declaration call_argument_list call_argument_list_nonempty for_declaration if_declaration
%type <param_list> parameter_list parameter_declaration parameter_list_nonempty

%%

statement:
	function_definition
	{
		/* handled in rule */
	}
	| function_prototype
	{
		/* handled in rule */
	}
	| CDECL_TYPEDEF qualified_type declarator_list ';'
	{
		register_typedef_declaration(&$2, $3);
		free_name_list($3);
		ecpg_c_parser_matched_flag = true;
	}
	| qualified_type init_declarator_list ';'
	{
		register_name_list(&$1, $2);
		free_name_list($2);
		ecpg_c_parser_matched_flag = true;
	}
	| qualified_type ';'
	{
		ecpg_c_parser_matched_flag = true;
	}
	| for_declaration
	| if_declaration
	;

function_definition:
	qualified_type declarator '(' parameter_list ')' '{'
	{
		register_parameter_list($4);
		c_parser_free_param_list($4);
		ecpg_c_parser_matched_flag = true;
	}
	| qualified_type declarator '(' CDECL_VOID ')' '{'
	{
		ecpg_c_parser_matched_flag = true;
	}
	;

function_prototype:
	qualified_type declarator '(' parameter_list ')' ';'
	{
		c_parser_free_param_list($4);
		ecpg_c_parser_matched_flag = true;
	}
	| qualified_type declarator '(' CDECL_VOID ')' ';'
	{
		ecpg_c_parser_matched_flag = true;
	}
	;

for_declaration:
	CDECL_FOR '(' qualified_type init_declarator_list ';' opt_assignment_expression ';' opt_assignment_expression ')' statement
	{
		register_name_list(&$3, $4);
		free_name_list($4);
		ecpg_c_parser_matched_flag = true;
	}
	;

if_declaration:
	CDECL_IF '(' qualified_type init_declarator_list ')' statement
	{
		register_name_list(&$3, $4);
		free_name_list($4);
		ecpg_c_parser_matched_flag = true;
	}
	| CDECL_IF '(' qualified_type init_declarator_list ')' statement CDECL_ELSE statement
	{
		register_name_list(&$3, $4);
		free_name_list($4);
		ecpg_c_parser_matched_flag = true;
	}
	;

qualified_type:
	simple_type
	{
		$$ = $1;
	}
	| type_qualifier_seq simple_type
	{
		$$ = $2;
	}
	| simple_type type_qualifier_seq
	{
		$$ = $1;
	}
	| type_qualifier_seq simple_type type_qualifier_seq
	{
		$$ = $2;
	}
	;

simple_type:
	CDECL_INT
	{
		$$.base_type = CDECL_BASE_INT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_CHAR
	{
		$$.base_type = CDECL_BASE_CHAR;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_FLOAT
	{
		$$.base_type = CDECL_BASE_FLOAT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_DOUBLE
	{
		$$.base_type = CDECL_BASE_DOUBLE;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_LONG
	{
		$$.base_type = CDECL_BASE_LONG;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_UNSIGNED CDECL_INT
	{
		$$.base_type = CDECL_BASE_UNSIGNED_INT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_BOOL
	{
		$$.base_type = CDECL_BASE_BOOL;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_VOID
	{
		$$.base_type = CDECL_BASE_VOID;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| struct_specifier
	{
		$$ = $1;
		$$.typedef_type = NULL;
	}
	| union_specifier
	{
		$$ = $1;
		$$.typedef_type = NULL;
	}
	| enum_specifier
	{
		$$ = $1;
		$$.typedef_type = NULL;
	}
	| CDECL_TYPE_NAME
	{
		CTypedef   *entry = c_parser_lookup_typedef_entry($1);

		if (entry == NULL)
			mmfatal(PARSE_ERROR, "typedef \"%s\" not found", $1);
		$$.base_type = CDECL_BASE_INT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = entry->type;
		free($1);
	}
	;

struct_specifier:
	CDECL_STRUCT CDECL_IDENTIFIER struct_body
	{
		c_parser_register_struct_def($2, $3);
		$$.base_type = CDECL_BASE_STRUCT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = mm_strdup($2);
		$$.struct_members = $3;
		$$.typedef_type = NULL;
	}
	| CDECL_STRUCT CDECL_IDENTIFIER
	{
		$$.base_type = CDECL_BASE_STRUCT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = mm_strdup($2);
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_STRUCT struct_body
	{
		char	   *anon_name = c_parser_make_anon_struct_name();

		c_parser_register_struct_def(anon_name, $2);
		$$.base_type = CDECL_BASE_STRUCT;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = anon_name;
		$$.struct_members = $2;
		$$.typedef_type = NULL;
	}
	;

union_specifier:
	CDECL_UNION CDECL_IDENTIFIER struct_body
	{
		c_parser_register_union_def($2, $3);
		$$.base_type = CDECL_BASE_UNION;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = mm_strdup($2);
		$$.struct_members = $3;
		$$.typedef_type = NULL;
	}
	| CDECL_UNION CDECL_IDENTIFIER
	{
		$$.base_type = CDECL_BASE_UNION;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = mm_strdup($2);
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_UNION struct_body
	{
		char	   *anon_name = c_parser_make_anon_union_name();

		c_parser_register_union_def(anon_name, $2);
		$$.base_type = CDECL_BASE_UNION;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = anon_name;
		$$.struct_members = $2;
		$$.typedef_type = NULL;
	}
	;

enum_specifier:
	CDECL_ENUM CDECL_IDENTIFIER '{' enumerator_list '}'
	{
		free($2);
		$$.base_type = CDECL_BASE_ENUM;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_ENUM '{' enumerator_list '}'
	{
		$$.base_type = CDECL_BASE_ENUM;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	| CDECL_ENUM CDECL_IDENTIFIER
	{
		free($2);
		$$.base_type = CDECL_BASE_ENUM;
		$$.pointer_level = 0;
		$$.array_dims = NULL;
		$$.struct_name = NULL;
		$$.struct_members = NULL;
		$$.typedef_type = NULL;
	}
	;

struct_body:
	'{' struct_field_list '}'
	{
		$$ = $2;
	}
	;

struct_field_list:
	struct_field_declaration
	{
		$$ = $1;
	}
	| struct_field_list struct_field_declaration
	{
		$$ = c_parser_append_struct_members($1, $2);
	}
	;

struct_field_declaration:
	qualified_type declarator_list ';'
	{
		$$ = c_parser_build_struct_members(&$1, $2);
		free_name_list($2);
	}
	;

init_declarator_list:
	init_declarator
	{
		$$ = $1;
	}
	| init_declarator_list ',' init_declarator
	{
		$$ = append_name_node($1, $3);
	}
	;

init_declarator:
	declarator initializer_opt
	{
		$$ = $1;
	}
	;

declarator_list:
	declarator
	{
		$$ = $1;
	}
	| declarator_list ',' declarator
	{
		$$ = append_name_node($1, $3);
	}
	;

declarator:
	pointer_opt CDECL_IDENTIFIER array_opt
	{
		$$ = make_name_node($2, $1, $3);
	}
	;

initializer_opt:
	/* empty */
	{
		$$ = 0;
	}
	| '=' initializer
	{
		$$ = 0;
	}
	;

initializer:
	assignment_expression
	{
		$$ = 0;
	}
	| '{' initializer_list '}'
	{
		$$ = 0;
	}
	| '{' initializer_list ',' '}'
	{
		$$ = 0;
	}
	;

initializer_list:
	initializer
	{
		$$ = 0;
	}
	| initializer_list ',' initializer
	{
		$$ = 0;
	}
	| designation initializer
	{
		$$ = 0;
	}
	| initializer_list ',' designation initializer
	{
		$$ = 0;
	}
	;

designation:
	designator_list '='
	{
		$$ = 0;
	}
	;

designator_list:
	designator
	{
		$$ = 0;
	}
	| designator_list designator
	{
		$$ = 0;
	}
	;

designator:
	'[' opt_assignment_expression ']'
	{
		$$ = 0;
	}
	| '.' CDECL_IDENTIFIER
	{
		free($2);
		$$ = 0;
	}
	;

opt_assignment_expression:
	/* empty */
	{
		$$ = 0;
	}
	| assignment_expression
	{
		$$ = 0;
	}
	;

assignment_expression:
	assignment_primary
	{
		$$ = 0;
	}
	| assignment_expression assignment_primary
	{
		$$ = 0;
	}
	;

assignment_primary:
	CDECL_NUMBER
	{
		free($1);
		$$ = 0;
	}
	| CDECL_IDENTIFIER
	{
		free($1);
		$$ = 0;
	}
	| CDECL_IDENTIFIER '(' call_argument_list ')'
	{
		free($1);
		$$ = 0;
	}
	| CDECL_STRING
	{
		free($1);
		$$ = 0;
	}
	| '(' assignment_expression ')'
	{
		$$ = 0;
	}
	| '[' assignment_expression ']'
	{
		$$ = 0;
	}
	| '+'
	{
		$$ = 0;
	}
	| '-'
	{
		$$ = 0;
	}
	| '*'
	{
		$$ = 0;
	}
	| '/'
	{
		$$ = 0;
	}
	| '%'
	{
		$$ = 0;
	}
	| '&'
	{
		$$ = 0;
	}
	| '|'
	{
		$$ = 0;
	}
	| '^'
	{
		$$ = 0;
	}
	| '~'
	{
		$$ = 0;
	}
	| '!'
	{
		$$ = 0;
	}
	| '?'
	{
		$$ = 0;
	}
	| ':'
	{
		$$ = 0;
	}
	| '.'
	{
		$$ = 0;
	}
	;

enumerator_list:
	enumerator
	{
		$$ = 0;
	}
	| enumerator_list ',' enumerator
	{
		$$ = 0;
	}
	;

enumerator:
	CDECL_IDENTIFIER
	{
		free($1);
		$$ = 0;
	}
	| CDECL_IDENTIFIER '=' assignment_expression
	{
		free($1);
		$$ = 0;
	}
	;

parameter_list:
	/* empty */
	{
		$$ = NULL;
	}
	| parameter_list_nonempty
	{
		$$ = $1;
	}
	;

abstract_parameter_list:
	/* empty */
	{
		$$ = 0;
	}
	| abstract_parameter_list_nonempty
	{
		$$ = 0;
	}
	;

abstract_parameter_list_nonempty:
	abstract_parameter_declaration
	{
		$$ = 0;
	}
	| abstract_parameter_list_nonempty ',' abstract_parameter_declaration
	{
		$$ = 0;
	}
	;

abstract_parameter_declaration:
	qualified_type
	{
		$$ = 0;
	}
	| qualified_type pointer_seq
	{
		$$ = 0;
	}
	| qualified_type pointer_seq CDECL_IDENTIFIER
	{
		free($3);
		$$ = 0;
	}
	| qualified_type declarator
	{
		if ($2)
			free_name_list($2);
		$$ = 0;
	}
	;

call_argument_list:
	/* empty */
	{
		$$ = 0;
	}
	| call_argument_list_nonempty
	{
		$$ = 0;
	}
	;

call_argument_list_nonempty:
	assignment_expression
	{
		$$ = 0;
	}
	| call_argument_list_nonempty ',' assignment_expression
	{
		$$ = 0;
	}
	;

function_pointer_parameter:
	'(' '*' pointer_opt CDECL_IDENTIFIER ')' '(' abstract_parameter_list ')' array_opt
	{
		int total_ptr = $3 + 1;

		(void) $7;
		$$ = make_name_node($4, total_ptr, $9);
	}
	;

parameter_list_nonempty:
	parameter_declaration
	{
		$$ = $1;
	}
	| parameter_list_nonempty ',' parameter_declaration
	{
		$$ = c_parser_append_param($1, $3);
	}
	;

parameter_declaration:
	qualified_type declarator
	{
		$$ = c_parser_make_param(&$1, $2);
	}
	| qualified_type function_pointer_parameter
	{
		$$ = c_parser_make_param(&$1, $2);
	}
	;

pointer_opt:
	/* empty */
	{
		$$ = 0;
	}
	| pointer_opt '*'
	{
		$$ = $1 + 1;
	}
	;

pointer_seq:
	'*'
	{
		$$ = 1;
	}
	| pointer_seq '*'
	{
		$$ = $1 + 1;
	}
	;

array_opt:
	/* empty */
	{
		$$ = NULL;
	}
	| array_dims
	{
		$$ = $1;
	}
	;

array_dims:
	'[' CDECL_NUMBER ']'
	{
		$$ = c_parser_make_array_dim($2);
	}
	| array_dims '[' CDECL_NUMBER ']'
	{
		$$ = c_parser_append_array_dim($1, c_parser_make_array_dim($3));
	}
	;

type_qualifier_seq:
	type_qualifier
	{
		$$ = 1;
	}
	| type_qualifier_seq type_qualifier
	{
		$$ = $1 + 1;
	}
	;

type_qualifier:
	CDECL_CONST
	{
		$$ = 1;
	}
	| CDECL_VOLATILE
	{
		$$ = 1;
	}
	;

%%

static struct ECPGtype *
build_simple_type(const CDeclType *type, const CDeclNameList *name)
{
	enum ECPGttype tt = ECPGt_int;
	struct ECPGtype *result;
	struct ECPGstruct_member *struct_members = NULL;

	if (type->typedef_type != NULL)
	{
		result = c_parser_dup_type(type->typedef_type);
		goto apply_name_decorations;
	}

	switch (type->base_type)
	{
		case CDECL_BASE_INT:
			tt = ECPGt_int;
			break;
		case CDECL_BASE_CHAR:
			tt = ECPGt_char;
			break;
		case CDECL_BASE_FLOAT:
			tt = ECPGt_float;
			break;
		case CDECL_BASE_DOUBLE:
			tt = ECPGt_double;
			break;
		case CDECL_BASE_LONG:
			tt = ECPGt_long;
			break;
		case CDECL_BASE_UNSIGNED_INT:
			tt = ECPGt_unsigned_int;
			break;
		case CDECL_BASE_BOOL:
			tt = ECPGt_bool;
			break;
		case CDECL_BASE_STRUCT:
		case CDECL_BASE_UNION:
			tt = ECPGt_struct;
			break;
		case CDECL_BASE_ENUM:
			tt = ECPGt_int;
			break;
		case CDECL_BASE_VOID:
			mmfatal(PARSE_ERROR, "\"void\" variables are not supported");
			break;
	}

	if (type->base_type == CDECL_BASE_STRUCT || type->base_type == CDECL_BASE_UNION)
	{
		const char *tag_kind = (type->base_type == CDECL_BASE_STRUCT) ? "struct" : "union";
		const char *struct_name = type->struct_name ? type->struct_name : "";
		char	   *struct_type_name = NULL;
		char	   *struct_sizeof_local = NULL;

		struct_members = type->struct_members;
		if (struct_members == NULL && type->struct_name)
			struct_members = (type->base_type == CDECL_BASE_STRUCT) ?
				c_parser_lookup_struct_def(type->struct_name) :
				c_parser_lookup_union_def(type->struct_name);
		if (struct_members == NULL)
			mmfatal(PARSE_ERROR, "%s \"%s\" is not defined",
					tag_kind,
					type->struct_name ? type->struct_name : "<anonymous>");

		if (type->struct_name)
		{
			struct_type_name = cat_str(3, tag_kind, " ", type->struct_name);
			struct_sizeof_local = cat_str(5, "sizeof(", tag_kind, " ", type->struct_name, ")");
		}

		result = ECPGmake_struct_type(struct_members, tt,
									  type->struct_name ? struct_type_name : struct_name,
									  type->struct_name ? struct_sizeof_local : "");
	}
	else
		result = ECPGmake_simple_type(tt, "1", 0);

apply_name_decorations:
	if (name->pointer_level > 2)
		mmfatal(PARSE_ERROR, "multilevel pointers (more than 2 levels) are not supported; found %d",
				name->pointer_level);

	if (name->pointer_level > 1 && !c_parser_is_char_pointer(tt))
		mmfatal(PARSE_ERROR, "pointer to pointer is not supported for this data type");

	for (int i = 0; i < name->pointer_level; i++)
		result = ECPGmake_array_type(result, "0");

	result = apply_array_dims(result, name->array_dims);

	return result;
}

static void
register_name_list(const CDeclType *type, CDeclNameList *list)
{
	register_name_list_at_level(type, list, ecpg_c_parser_current_brace_level);
}

static void
register_simple_declaration_at_level(const CDeclType *type, const CDeclNameList *name, int level)
{
	struct ECPGtype *t = build_simple_type(type, name);

	new_variable(name->name, t, level);
}

static void
register_name_list_at_level(const CDeclType *type, CDeclNameList *list, int level)
{
	CDeclNameList *iter;

	for (iter = list; iter != NULL; iter = iter->next)
		register_simple_declaration_at_level(type, iter, level);
}

static CDeclNameList *
make_name_node(char *name, int pointer_level, struct array_dim *array_dims)
{
	CDeclNameList *node = (CDeclNameList *) mm_alloc(sizeof(CDeclNameList));

	node->name = name;
	node->pointer_level = pointer_level;
	node->array_dims = array_dims;
	node->next = NULL;
	return node;
}

static CDeclNameList *
append_name_node(CDeclNameList *list, CDeclNameList *tail)
{
	CDeclNameList *iter;

	if (list == NULL)
		return tail;

	iter = list;
	while (iter->next)
		iter = iter->next;

	iter->next = tail;
	return list;
}

static void
free_name_list(CDeclNameList *list)
{
	CDeclNameList *next;

	while (list)
	{
		next = list->next;
		free(list->name);
		c_parser_free_array_dims(list->array_dims);
		free(list);
		list = next;
	}
}

static bool
c_parser_is_char_pointer(enum ECPGttype type)
{
	return type == ECPGt_char || type == ECPGt_unsigned_char;
}

void
c_parser_error(const char *msg)
{
	if (getenv("ECPG_DEBUG_CDECL"))
		fprintf(stderr, "[ECPG cdecl] parse error: %s\n", msg);
}
static struct array_dim *
c_parser_make_array_dim(char *size)
{
	struct array_dim *dim = (struct array_dim *) mm_alloc(sizeof(struct array_dim));

	dim->size = size;
	dim->next = NULL;
	return dim;
}

static struct array_dim *
c_parser_append_array_dim(struct array_dim *list, struct array_dim *dim)
{
	struct array_dim *iter;

	if (list == NULL)
		return dim;

	iter = list;
	while (iter->next)
		iter = iter->next;

	iter->next = dim;
	return list;
}

static void
c_parser_free_array_dims(struct array_dim *list)
{
	struct array_dim *next;

	while (list)
	{
		next = list->next;
		if (list->size)
			free(list->size);
		free(list);
		list = next;
	}
}

static struct ECPGtype *
apply_array_dims(struct ECPGtype *type, struct array_dim *dims)
{
	if (dims == NULL)
		return type;

	type = apply_array_dims(type, dims->next);
	return ECPGmake_array_type(type, dims->size);
}

static void
c_parser_register_struct_def(const char *name, struct ECPGstruct_member *members)
{
	CStructDef *iter;

	for (iter = c_parser_struct_defs; iter != NULL; iter = iter->next)
	{
		if (strcmp(iter->name, name) == 0)
		{
			ECPGfree_struct_member(iter->members);
			iter->members = ECPGstruct_member_dup(members);
			return;
		}
	}

	iter = (CStructDef *) mm_alloc(sizeof(CStructDef));
	iter->name = mm_strdup(name);
	iter->members = ECPGstruct_member_dup(members);
	iter->next = c_parser_struct_defs;
	c_parser_struct_defs = iter;
}

static void
c_parser_register_union_def(const char *name, struct ECPGstruct_member *members)
{
	CUnionDef *iter;

	for (iter = c_parser_union_defs; iter != NULL; iter = iter->next)
	{
		if (strcmp(iter->name, name) == 0)
		{
			ECPGfree_struct_member(iter->members);
			iter->members = ECPGstruct_member_dup(members);
			return;
		}
	}

	iter = (CUnionDef *) mm_alloc(sizeof(CUnionDef));
	iter->name = mm_strdup(name);
	iter->members = ECPGstruct_member_dup(members);
	iter->next = c_parser_union_defs;
	c_parser_union_defs = iter;
}

static struct ECPGstruct_member *
c_parser_lookup_struct_def(const char *name)
{
	CStructDef *iter;

	for (iter = c_parser_struct_defs; iter != NULL; iter = iter->next)
	{
		if (strcmp(iter->name, name) == 0)
			return iter->members;
	}
	return NULL;
}

static struct ECPGstruct_member *
c_parser_lookup_union_def(const char *name)
{
	CUnionDef *iter;

	for (iter = c_parser_union_defs; iter != NULL; iter = iter->next)
	{
		if (strcmp(iter->name, name) == 0)
			return iter->members;
	}
	return NULL;
}

static char *
c_parser_make_anon_struct_name(void)
{
	char		buf[64];

	snprintf(buf, sizeof(buf), "__ecpg_anon_struct_%d", ++c_parser_anon_struct_id);
	return mm_strdup(buf);
}

static char *
c_parser_make_anon_union_name(void)
{
	char		buf[64];

	snprintf(buf, sizeof(buf), "__ecpg_anon_union_%d", ++c_parser_anon_union_id);
	return mm_strdup(buf);
}

static struct ECPGstruct_member *
c_parser_build_struct_members(const CDeclType *type, CDeclNameList *names)
{
	struct ECPGstruct_member *members = NULL;
	CDeclNameList *iter;

	for (iter = names; iter != NULL; iter = iter->next)
	{
		CDeclNameList temp = *iter;

		temp.next = NULL;
		ECPGmake_struct_member(iter->name,
							   build_simple_type(type, &temp),
							   &members);
	}

	return members;
}

static struct ECPGstruct_member *
c_parser_append_struct_members(struct ECPGstruct_member *list,
							   struct ECPGstruct_member *tail)
{
	struct ECPGstruct_member *iter;

	if (list == NULL)
		return tail;

	iter = list;
	while (iter->next)
		iter = iter->next;

	iter->next = tail;
	return list;
}

static void
register_parameter_list(CParamDecl *params)
{
	CParamDecl *iter;
	int			level = ecpg_c_parser_current_brace_level + 1;

	for (iter = params; iter != NULL; iter = iter->next)
	{
		if (iter->name == NULL)
			continue;
		if (iter->type.base_type == CDECL_BASE_VOID)
		{
			free_name_list(iter->name);
			iter->name = NULL;
			continue;
		}
		register_name_list_at_level(&iter->type, iter->name, level);
	}
}

static CParamDecl *
c_parser_make_param(CDeclType *type, CDeclNameList *name)
{
	CParamDecl *param;

	if (name == NULL)
		return NULL;

	param = (CParamDecl *) mm_alloc(sizeof(CParamDecl));
	param->type = *type;
	param->name = name;
	param->next = NULL;
	return param;
}

static CParamDecl *
c_parser_append_param(CParamDecl *list, CParamDecl *tail)
{
	CParamDecl *iter;

	if (list == NULL)
		return tail;
	if (tail == NULL)
		return list;

	iter = list;
	while (iter->next)
		iter = iter->next;
	iter->next = tail;
	return list;
}

static void
c_parser_free_param_list(CParamDecl *list)
{
	CParamDecl *next;

	while (list)
	{
		next = list->next;
		if (list->name)
			free_name_list(list->name);
		free(list);
		list = next;
	}
}

static void
register_typedef_declaration(const CDeclType *type, CDeclNameList *list)
{
	CDeclNameList *iter;

	for (iter = list; iter != NULL; iter = iter->next)
	{
		struct ECPGtype *t = build_simple_type(type, iter);

		c_parser_add_typedef(iter->name, t);
	}
}

static void
c_parser_free_typedef_entry(CTypedef *entry)
{
	if (entry == NULL)
		return;

	if (entry->type)
		ECPGfree_type(entry->type);
	if (entry->name)
		free(entry->name);
	free(entry);
}

static void
c_parser_remove_typedef_same_level(const char *name, int level)
{
	CTypedef   *prev = NULL;
	CTypedef   *iter = c_parser_typedefs;

	while (iter)
	{
		if (iter->brace_level == level && strcmp(iter->name, name) == 0)
		{
			if (prev)
				prev->next = iter->next;
			else
				c_parser_typedefs = iter->next;
			c_parser_free_typedef_entry(iter);
			return;
		}

		prev = iter;
		iter = iter->next;
	}
}

static void
c_parser_add_typedef(const char *name, struct ECPGtype *type)
{
	CTypedef   *entry;

	c_parser_remove_typedef_same_level(name, ecpg_c_parser_current_brace_level);

	entry = (CTypedef *) mm_alloc(sizeof(CTypedef));
	entry->name = mm_strdup(name);
	entry->type = type;
	entry->brace_level = ecpg_c_parser_current_brace_level;
	entry->next = c_parser_typedefs;
	c_parser_typedefs = entry;
}

static struct ECPGtype *
c_parser_dup_type(const struct ECPGtype *type)
{
	struct ECPGtype *copy;

	if (type == NULL)
		return NULL;

	copy = (struct ECPGtype *) mm_alloc(sizeof(struct ECPGtype));
	copy->type = type->type;
	copy->type_name = type->type_name ? mm_strdup(type->type_name) : NULL;
	copy->size = type->size ? mm_strdup(type->size) : NULL;
	copy->struct_sizeof = type->struct_sizeof ? mm_strdup(type->struct_sizeof) : NULL;
	copy->counter = type->counter;

	switch (type->type)
	{
		case ECPGt_array:
			copy->u.element = c_parser_dup_type(type->u.element);
			break;
		case ECPGt_struct:
			copy->u.members = ECPGstruct_member_dup(type->u.members);
			break;
		default:
			copy->u.element = NULL;
			break;
	}

	return copy;
}

static CTypedef *
c_parser_lookup_typedef_entry(const char *name)
{
	CTypedef   *iter;

	for (iter = c_parser_typedefs; iter != NULL; iter = iter->next)
	{
		if (strcmp(iter->name, name) == 0)
			return iter;
	}
	return NULL;
}

bool
ecpg_c_parser_is_typedef_name(const char *name)
{
	return c_parser_lookup_typedef_entry(name) != NULL;
}

void
ecpg_c_parser_remove_typedefs(int brace_level)
{
	CTypedef   *prev = NULL;
	CTypedef   *iter = c_parser_typedefs;

	while (iter)
	{
		CTypedef   *next = iter->next;

		if (iter->brace_level >= brace_level)
		{
			if (prev)
				prev->next = next;
			else
				c_parser_typedefs = next;
			c_parser_free_typedef_entry(iter);
		}
		else
			prev = iter;

		iter = next;
	}
}
