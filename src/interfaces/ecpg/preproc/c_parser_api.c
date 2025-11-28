#include "postgres_fe.h"

#include "preproc_extern.h"
#include "c_parser.h"
#include "c_parser.tab.h"

typedef struct yy_buffer_state *YY_BUFFER_STATE;
extern YY_BUFFER_STATE c_parser__scan_string(const char *);
extern void c_parser__delete_buffer(YY_BUFFER_STATE);

static char *c_decl_buffer = NULL;
static size_t c_decl_buflen = 0;
static size_t c_decl_bufcap = 0;

static bool
ecpg_c_decl_debug_enabled(void)
{
	static bool initialized = false;
	static bool enabled = false;

	if (!initialized)
	{
		enabled = (getenv("ECPG_DEBUG_CDECL") != NULL);
		initialized = true;
	}

	return enabled;
}

static void
ensure_buffer(size_t extra)
{
	if (c_decl_buflen + extra + 1 <= c_decl_bufcap)
		return;

	while (c_decl_buflen + extra + 1 > c_decl_bufcap)
		c_decl_bufcap = (c_decl_bufcap > 0) ? c_decl_bufcap * 2 : 256;

	c_decl_buffer = realloc(c_decl_buffer, c_decl_bufcap);
	if (c_decl_buffer == NULL)
		mmfatal(OUT_OF_MEMORY, "out of memory");
}

void
ecpg_c_parser_init(void)
{
	c_decl_buflen = 0;
	c_decl_bufcap = 0;
	c_decl_buffer = NULL;
	ecpg_c_parser_remove_typedefs(0);
}

void
ecpg_c_parser_reset(void)
{
	c_decl_buflen = 0;
	if (c_decl_buffer)
		c_decl_buffer[0] = '\0';
}

void
ecpg_c_parser_append(const char *str, int len)
{
	if (!str || len <= 0)
		return;

	ensure_buffer(len);
	memcpy(c_decl_buffer + c_decl_buflen, str, len);
	c_decl_buflen += len;
	c_decl_buffer[c_decl_buflen] = '\0';
}

bool
ecpg_c_parser_process_statement(int brace_level)
{
	YY_BUFFER_STATE buf;
	bool		debug = ecpg_c_decl_debug_enabled();

	if (c_decl_buflen == 0)
		return false;

	if (debug)
		fprintf(stderr, "[ECPG cdecl] input: \"%s\"\n", c_decl_buffer);

	buf = c_parser__scan_string(c_decl_buffer);
	ecpg_c_parser_set_brace_level(brace_level);
	ecpg_c_parser_reset_match();
	c_parser_parse();
	c_parser__delete_buffer(buf);
	ecpg_c_parser_reset();

	if (debug)
		fprintf(stderr, "[ECPG cdecl] %s\n",
				ecpg_c_parser_matched_declaration() ? "matched" : "ignored");

	return ecpg_c_parser_matched_declaration();
}
