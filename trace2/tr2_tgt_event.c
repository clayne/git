#define DISABLE_SIGN_COMPARE_WARNINGS

#include "git-compat-util.h"
#include "config.h"
#include "json-writer.h"
#include "repository.h"
#include "run-command.h"
#include "version.h"
#include "trace2/tr2_dst.h"
#include "trace2/tr2_tbuf.h"
#include "trace2/tr2_sid.h"
#include "trace2/tr2_sysenv.h"
#include "trace2/tr2_tgt.h"
#include "trace2/tr2_tls.h"
#include "trace2/tr2_tmr.h"

static struct tr2_dst tr2dst_event = {
	.sysenv_var = TR2_SYSENV_EVENT,
};

/*
 * The version number of the JSON data generated by the EVENT target in this
 * source file. The version should be incremented if new event types are added,
 * if existing fields are removed, or if there are significant changes in
 * interpretation of existing events or fields. Smaller changes, such as adding
 * a new field to an existing event, do not require an increment to the EVENT
 * format version.
 */
#define TR2_EVENT_VERSION "4"

/*
 * Region nesting limit for messages written to the event target.
 *
 * The "region_enter" and "region_leave" messages (especially recursive
 * messages such as those produced while diving the worktree or index)
 * are primarily intended for the performance target during debugging.
 *
 * Some of the outer-most messages, however, may be of interest to the
 * event target.  Use the TR2_SYSENV_EVENT_NESTING setting to increase
 * region details in the event target.
 */
static int tr2env_event_max_nesting_levels = 4;

/*
 * Use the TR2_SYSENV_EVENT_BRIEF to omit the <time>, <file>, and
 * <line> fields from most events.
 */
static int tr2env_event_be_brief;

static int fn_init(void)
{
	int want = tr2_dst_trace_want(&tr2dst_event);
	int max_nesting;
	int want_brief;
	const char *nesting;
	const char *brief;

	if (!want)
		return want;

	nesting = tr2_sysenv_get(TR2_SYSENV_EVENT_NESTING);
	if (nesting && *nesting && ((max_nesting = atoi(nesting)) > 0))
		tr2env_event_max_nesting_levels = max_nesting;

	brief = tr2_sysenv_get(TR2_SYSENV_EVENT_BRIEF);
	if (brief && *brief &&
	    ((want_brief = git_parse_maybe_bool(brief)) != -1))
		tr2env_event_be_brief = want_brief;

	return want;
}

static void fn_term(void)
{
	tr2_dst_trace_disable(&tr2dst_event);
}

/*
 * Append common key-value pairs to the currently open JSON object.
 *     "event:"<event_name>"
 *      "sid":"<sid>"
 *   "thread":"<thread_name>"
 *     "time":"<time>"
 *     "file":"<filename>"
 *     "line":<line_number>
 *     "repo":<repo_id>
 */
static void event_fmt_prepare(const char *event_name, const char *file,
			      int line, const struct repository *repo,
			      struct json_writer *jw)
{
	struct tr2tls_thread_ctx *ctx = tr2tls_get_self();
	struct tr2_tbuf tb_now;

	jw_object_string(jw, "event", event_name);
	jw_object_string(jw, "sid", tr2_sid_get());
	jw_object_string(jw, "thread", ctx->thread_name);

	/*
	 * In brief mode, only emit <time> on these 2 event types.
	 */
	if (!tr2env_event_be_brief || !strcmp(event_name, "version") ||
	    !strcmp(event_name, "atexit")) {
		tr2_tbuf_utc_datetime_extended(&tb_now);
		jw_object_string(jw, "time", tb_now.buf);
	}

	if (!tr2env_event_be_brief && file && *file) {
		jw_object_string(jw, "file", file);
		jw_object_intmax(jw, "line", line);
	}

	if (repo)
		jw_object_intmax(jw, "repo", repo->trace2_repo_id);
}

static void fn_too_many_files_fl(const char *file, int line)
{
	const char *event_name = "too_many_files";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_version_fl(const char *file, int line)
{
	const char *event_name = "version";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "evt", TR2_EVENT_VERSION);
	jw_object_string(&jw, "exe", git_version_string);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);

	if (tr2dst_event.too_many_files)
		fn_too_many_files_fl(file, line);
}

static void fn_start_fl(const char *file, int line,
			uint64_t us_elapsed_absolute, const char **argv)
{
	const char *event_name = "start";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_abs = (double)us_elapsed_absolute / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_double(&jw, "t_abs", 6, t_abs);
	jw_object_inline_begin_array(&jw, "argv");
	jw_array_argv(&jw, argv);
	jw_end(&jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_exit_fl(const char *file, int line, uint64_t us_elapsed_absolute,
		       int code)
{
	const char *event_name = "exit";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_abs = (double)us_elapsed_absolute / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_double(&jw, "t_abs", 6, t_abs);
	jw_object_intmax(&jw, "code", code);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_signal(uint64_t us_elapsed_absolute, int signo)
{
	const char *event_name = "signal";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_abs = (double)us_elapsed_absolute / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, __FILE__, __LINE__, NULL, &jw);
	jw_object_double(&jw, "t_abs", 6, t_abs);
	jw_object_intmax(&jw, "signo", signo);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_atexit(uint64_t us_elapsed_absolute, int code)
{
	const char *event_name = "atexit";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_abs = (double)us_elapsed_absolute / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, __FILE__, __LINE__, NULL, &jw);
	jw_object_double(&jw, "t_abs", 6, t_abs);
	jw_object_intmax(&jw, "code", code);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void maybe_add_string_va(struct json_writer *jw, const char *field_name,
				const char *fmt, va_list ap)
{
	if (fmt && *fmt) {
		va_list copy_ap;
		struct strbuf buf = STRBUF_INIT;

		va_copy(copy_ap, ap);
		strbuf_vaddf(&buf, fmt, copy_ap);
		va_end(copy_ap);

		jw_object_string(jw, field_name, buf.buf);
		strbuf_release(&buf);
		return;
	}
}

static void fn_error_va_fl(const char *file, int line, const char *fmt,
			   va_list ap)
{
	const char *event_name = "error";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	maybe_add_string_va(&jw, "msg", fmt, ap);
	/*
	 * Also emit the format string as a field in case
	 * post-processors want to aggregate common error
	 * messages by type without argument fields (such
	 * as pathnames or branch names) cluttering it up.
	 */
	if (fmt && *fmt)
		jw_object_string(&jw, "fmt", fmt);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_command_path_fl(const char *file, int line, const char *pathname)
{
	const char *event_name = "cmd_path";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "path", pathname);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_command_ancestry_fl(const char *file, int line, const char **parent_names)
{
	const char *event_name = "cmd_ancestry";
	const char *parent_name = NULL;
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_inline_begin_array(&jw, "ancestry");

	while ((parent_name = *parent_names++))
		jw_array_string(&jw, parent_name);

	jw_end(&jw); /* 'ancestry' array */
	jw_end(&jw); /* event object */

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_command_name_fl(const char *file, int line, const char *name,
			       const char *hierarchy)
{
	const char *event_name = "cmd_name";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "name", name);
	if (hierarchy && *hierarchy)
		jw_object_string(&jw, "hierarchy", hierarchy);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_command_mode_fl(const char *file, int line, const char *mode)
{
	const char *event_name = "cmd_mode";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "name", mode);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_alias_fl(const char *file, int line, const char *alias,
			const char **argv)
{
	const char *event_name = "alias";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "alias", alias);
	jw_object_inline_begin_array(&jw, "argv");
	jw_array_argv(&jw, argv);
	jw_end(&jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_child_start_fl(const char *file, int line,
			      uint64_t us_elapsed_absolute UNUSED,
			      const struct child_process *cmd)
{
	const char *event_name = "child_start";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_intmax(&jw, "child_id", cmd->trace2_child_id);
	if (cmd->trace2_hook_name) {
		jw_object_string(&jw, "child_class", "hook");
		jw_object_string(&jw, "hook_name", cmd->trace2_hook_name);
	} else {
		const char *child_class =
			cmd->trace2_child_class ? cmd->trace2_child_class : "?";
		jw_object_string(&jw, "child_class", child_class);
	}
	if (cmd->dir)
		jw_object_string(&jw, "cd", cmd->dir);
	jw_object_bool(&jw, "use_shell", cmd->use_shell);
	jw_object_inline_begin_array(&jw, "argv");
	if (cmd->git_cmd)
		jw_array_string(&jw, "git");
	jw_array_argv(&jw, cmd->args.v);
	jw_end(&jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_child_exit_fl(const char *file, int line,
			     uint64_t us_elapsed_absolute UNUSED,
			     int cid, int pid,
			     int code, uint64_t us_elapsed_child)
{
	const char *event_name = "child_exit";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_rel = (double)us_elapsed_child / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_intmax(&jw, "child_id", cid);
	jw_object_intmax(&jw, "pid", pid);
	jw_object_intmax(&jw, "code", code);
	jw_object_double(&jw, "t_rel", 6, t_rel);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);

	jw_release(&jw);
}

static void fn_child_ready_fl(const char *file, int line,
			      uint64_t us_elapsed_absolute UNUSED,
			      int cid, int pid,
			      const char *ready, uint64_t us_elapsed_child)
{
	const char *event_name = "child_ready";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_rel = (double)us_elapsed_child / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_intmax(&jw, "child_id", cid);
	jw_object_intmax(&jw, "pid", pid);
	jw_object_string(&jw, "ready", ready);
	jw_object_double(&jw, "t_rel", 6, t_rel);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);

	jw_release(&jw);
}

static void fn_thread_start_fl(const char *file, int line,
			       uint64_t us_elapsed_absolute UNUSED)
{
	const char *event_name = "thread_start";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_thread_exit_fl(const char *file, int line,
			      uint64_t us_elapsed_absolute UNUSED,
			      uint64_t us_elapsed_thread)
{
	const char *event_name = "thread_exit";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_rel = (double)us_elapsed_thread / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_double(&jw, "t_rel", 6, t_rel);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_exec_fl(const char *file, int line,
		       uint64_t us_elapsed_absolute UNUSED,
		       int exec_id, const char *exe, const char **argv)
{
	const char *event_name = "exec";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_intmax(&jw, "exec_id", exec_id);
	if (exe)
		jw_object_string(&jw, "exe", exe);
	jw_object_inline_begin_array(&jw, "argv");
	jw_array_argv(&jw, argv);
	jw_end(&jw);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_exec_result_fl(const char *file, int line,
			      uint64_t us_elapsed_absolute UNUSED,
			      int exec_id, int code)
{
	const char *event_name = "exec_result";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_intmax(&jw, "exec_id", exec_id);
	jw_object_intmax(&jw, "code", code);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_param_fl(const char *file, int line, const char *param,
			const char *value, const struct key_value_info *kvi)
{
	const char *event_name = "def_param";
	struct json_writer jw = JSON_WRITER_INIT;
	enum config_scope scope = kvi->scope;
	const char *scope_name = config_scope_name(scope);

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_string(&jw, "scope", scope_name);
	jw_object_string(&jw, "param", param);
	if (value)
		jw_object_string(&jw, "value", value);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_repo_fl(const char *file, int line,
		       const struct repository *repo)
{
	const char *event_name = "def_repo";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, repo, &jw);
	jw_object_string(&jw, "worktree", repo->worktree);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_region_enter_printf_va_fl(const char *file, int line,
					 uint64_t us_elapsed_absolute UNUSED,
					 const char *category,
					 const char *label,
					 const struct repository *repo,
					 const char *fmt, va_list ap)
{
	const char *event_name = "region_enter";
	struct tr2tls_thread_ctx *ctx = tr2tls_get_self();
	if (ctx->nr_open_regions <= tr2env_event_max_nesting_levels) {
		struct json_writer jw = JSON_WRITER_INIT;

		jw_object_begin(&jw, 0);
		event_fmt_prepare(event_name, file, line, repo, &jw);
		jw_object_intmax(&jw, "nesting", ctx->nr_open_regions);
		if (category)
			jw_object_string(&jw, "category", category);
		if (label)
			jw_object_string(&jw, "label", label);
		maybe_add_string_va(&jw, "msg", fmt, ap);
		jw_end(&jw);

		tr2_dst_write_line(&tr2dst_event, &jw.json);
		jw_release(&jw);
	}
}

static void fn_region_leave_printf_va_fl(
	const char *file, int line, uint64_t us_elapsed_absolute UNUSED,
	uint64_t us_elapsed_region, const char *category, const char *label,
	const struct repository *repo, const char *fmt, va_list ap)
{
	const char *event_name = "region_leave";
	struct tr2tls_thread_ctx *ctx = tr2tls_get_self();
	if (ctx->nr_open_regions <= tr2env_event_max_nesting_levels) {
		struct json_writer jw = JSON_WRITER_INIT;
		double t_rel = (double)us_elapsed_region / 1000000.0;

		jw_object_begin(&jw, 0);
		event_fmt_prepare(event_name, file, line, repo, &jw);
		jw_object_double(&jw, "t_rel", 6, t_rel);
		jw_object_intmax(&jw, "nesting", ctx->nr_open_regions);
		if (category)
			jw_object_string(&jw, "category", category);
		if (label)
			jw_object_string(&jw, "label", label);
		maybe_add_string_va(&jw, "msg", fmt, ap);
		jw_end(&jw);

		tr2_dst_write_line(&tr2dst_event, &jw.json);
		jw_release(&jw);
	}
}

static void fn_data_fl(const char *file, int line, uint64_t us_elapsed_absolute,
		       uint64_t us_elapsed_region, const char *category,
		       const struct repository *repo, const char *key,
		       const char *value)
{
	const char *event_name = "data";
	struct tr2tls_thread_ctx *ctx = tr2tls_get_self();
	if (ctx->nr_open_regions <= tr2env_event_max_nesting_levels) {
		struct json_writer jw = JSON_WRITER_INIT;
		double t_abs = (double)us_elapsed_absolute / 1000000.0;
		double t_rel = (double)us_elapsed_region / 1000000.0;

		jw_object_begin(&jw, 0);
		event_fmt_prepare(event_name, file, line, repo, &jw);
		jw_object_double(&jw, "t_abs", 6, t_abs);
		jw_object_double(&jw, "t_rel", 6, t_rel);
		jw_object_intmax(&jw, "nesting", ctx->nr_open_regions);
		jw_object_string(&jw, "category", category);
		jw_object_string(&jw, "key", key);
		jw_object_string(&jw, "value", value);
		jw_end(&jw);

		tr2_dst_write_line(&tr2dst_event, &jw.json);
		jw_release(&jw);
	}
}

static void fn_data_json_fl(const char *file, int line,
			    uint64_t us_elapsed_absolute,
			    uint64_t us_elapsed_region, const char *category,
			    const struct repository *repo, const char *key,
			    const struct json_writer *value)
{
	const char *event_name = "data_json";
	struct tr2tls_thread_ctx *ctx = tr2tls_get_self();
	if (ctx->nr_open_regions <= tr2env_event_max_nesting_levels) {
		struct json_writer jw = JSON_WRITER_INIT;
		double t_abs = (double)us_elapsed_absolute / 1000000.0;
		double t_rel = (double)us_elapsed_region / 1000000.0;

		jw_object_begin(&jw, 0);
		event_fmt_prepare(event_name, file, line, repo, &jw);
		jw_object_double(&jw, "t_abs", 6, t_abs);
		jw_object_double(&jw, "t_rel", 6, t_rel);
		jw_object_intmax(&jw, "nesting", ctx->nr_open_regions);
		jw_object_string(&jw, "category", category);
		jw_object_string(&jw, "key", key);
		jw_object_sub_jw(&jw, "value", value);
		jw_end(&jw);

		tr2_dst_write_line(&tr2dst_event, &jw.json);
		jw_release(&jw);
	}
}

static void fn_printf_va_fl(const char *file, int line,
			    uint64_t us_elapsed_absolute,
			    const char *fmt, va_list ap)
{
	const char *event_name = "printf";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_abs = (double)us_elapsed_absolute / 1000000.0;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, file, line, NULL, &jw);
	jw_object_double(&jw, "t_abs", 6, t_abs);
	maybe_add_string_va(&jw, "msg", fmt, ap);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_timer(const struct tr2_timer_metadata *meta,
		     const struct tr2_timer *timer,
		     int is_final_data)
{
	const char *event_name = is_final_data ? "timer" : "th_timer";
	struct json_writer jw = JSON_WRITER_INIT;
	double t_total = NS_TO_SEC(timer->total_ns);
	double t_min = NS_TO_SEC(timer->min_ns);
	double t_max = NS_TO_SEC(timer->max_ns);

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, __FILE__, __LINE__, NULL, &jw);
	jw_object_string(&jw, "category", meta->category);
	jw_object_string(&jw, "name", meta->name);
	jw_object_intmax(&jw, "intervals", timer->interval_count);
	jw_object_double(&jw, "t_total", 6, t_total);
	jw_object_double(&jw, "t_min", 6, t_min);
	jw_object_double(&jw, "t_max", 6, t_max);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

static void fn_counter(const struct tr2_counter_metadata *meta,
		       const struct tr2_counter *counter,
		       int is_final_data)
{
	const char *event_name = is_final_data ? "counter" : "th_counter";
	struct json_writer jw = JSON_WRITER_INIT;

	jw_object_begin(&jw, 0);
	event_fmt_prepare(event_name, __FILE__, __LINE__, NULL, &jw);
	jw_object_string(&jw, "category", meta->category);
	jw_object_string(&jw, "name", meta->name);
	jw_object_intmax(&jw, "count", counter->value);
	jw_end(&jw);

	tr2_dst_write_line(&tr2dst_event, &jw.json);
	jw_release(&jw);
}

struct tr2_tgt tr2_tgt_event = {
	.pdst = &tr2dst_event,

	.pfn_init = fn_init,
	.pfn_term = fn_term,

	.pfn_version_fl = fn_version_fl,
	.pfn_start_fl = fn_start_fl,
	.pfn_exit_fl = fn_exit_fl,
	.pfn_signal = fn_signal,
	.pfn_atexit = fn_atexit,
	.pfn_error_va_fl = fn_error_va_fl,
	.pfn_command_path_fl = fn_command_path_fl,
	.pfn_command_ancestry_fl = fn_command_ancestry_fl,
	.pfn_command_name_fl = fn_command_name_fl,
	.pfn_command_mode_fl = fn_command_mode_fl,
	.pfn_alias_fl = fn_alias_fl,
	.pfn_child_start_fl = fn_child_start_fl,
	.pfn_child_exit_fl = fn_child_exit_fl,
	.pfn_child_ready_fl = fn_child_ready_fl,
	.pfn_thread_start_fl = fn_thread_start_fl,
	.pfn_thread_exit_fl = fn_thread_exit_fl,
	.pfn_exec_fl = fn_exec_fl,
	.pfn_exec_result_fl = fn_exec_result_fl,
	.pfn_param_fl = fn_param_fl,
	.pfn_repo_fl = fn_repo_fl,
	.pfn_region_enter_printf_va_fl = fn_region_enter_printf_va_fl,
	.pfn_region_leave_printf_va_fl = fn_region_leave_printf_va_fl,
	.pfn_data_fl = fn_data_fl,
	.pfn_data_json_fl = fn_data_json_fl,
	.pfn_printf_va_fl = fn_printf_va_fl,
	.pfn_timer = fn_timer,
	.pfn_counter = fn_counter,
};
