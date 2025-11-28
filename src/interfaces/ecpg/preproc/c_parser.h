#ifndef ECPG_C_PARSER_H
#define ECPG_C_PARSER_H

#include <stdbool.h>

#include "preproc_extern.h"

typedef enum CDeclBaseType
{
	CDECL_BASE_INT,
	CDECL_BASE_CHAR,
	CDECL_BASE_FLOAT,
	CDECL_BASE_DOUBLE,
	CDECL_BASE_LONG,
	CDECL_BASE_UNSIGNED_INT,
	CDECL_BASE_BOOL,
	CDECL_BASE_STRUCT,
	CDECL_BASE_UNION,
	CDECL_BASE_ENUM,
	CDECL_BASE_VOID
} CDeclBaseType;

typedef struct CDeclType
{
	CDeclBaseType base_type;
	int		pointer_level;
	struct array_dim *array_dims;
	char	   *struct_name;
	struct ECPGstruct_member *struct_members;
	struct ECPGtype *typedef_type;
} CDeclType;

typedef struct CDeclNameList CDeclNameList;
typedef struct CParamDecl CParamDecl;

void ecpg_c_parser_init(void);
void ecpg_c_parser_reset(void);
void ecpg_c_parser_append(const char *str, int len);
bool ecpg_c_parser_process_statement(int brace_level);

void ecpg_c_parser_set_brace_level(int level);
void ecpg_c_parser_reset_match(void);
bool ecpg_c_parser_matched_declaration(void);
bool ecpg_c_parser_has_buffer(void);
bool ecpg_c_parser_buffer_has_initializer(void);
bool ecpg_c_parser_is_typedef_name(const char *name);
void ecpg_c_parser_remove_typedefs(int brace_level);

#endif
