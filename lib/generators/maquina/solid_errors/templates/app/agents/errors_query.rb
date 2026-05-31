# Read-only queries over the Solid Errors store, shaped for agent consumption.
#
# This layer NEVER writes. Resolution, retry, and discard stay with the human in
# the Backstage dashboards. Every context hash and job argument list passes
# through ErrorRedactor before leaving this class.
#
# Failed background jobs reach Solid Errors through the Rails error reporter and
# carry the job class/arguments attached by ApplicationJob's around_perform hook,
# so a single read here covers both request and job failures.
#
# Column and association names (fingerprint, occurrences_count, recent_occurrence,
# parsed_backtrace) follow the solid_errors gem schema; confirm against your
# generated db/errors_schema.rb if you pin an unusual version.
class ErrorsQuery
  DEFAULT_LIMIT = 25
  TOP_LIMIT = 10
  BACKTRACE_LIMIT = 50

  class << self
    def unresolved(limit: DEFAULT_LIMIT)
      SolidErrors::Error.where(resolved_at: nil)
        .order(created_at: :desc)
        .limit(limit)
        .map { |error| summarize(error) }
    end

    def top(limit: TOP_LIMIT)
      SolidErrors::Error.where(resolved_at: nil)
        .order(occurrences_count: :desc)
        .limit(limit)
        .map { |error| summarize(error) }
    end

    def find(fingerprint)
      detail(SolidErrors::Error.find_by!(fingerprint: fingerprint))
    end

    private

    def summarize(error)
      {
        fingerprint: error.fingerprint,
        exception: error.exception_class,
        message: error.message,
        occurrences: error.occurrences_count,
        last_seen: error.recent_occurrence&.created_at,
        job: job_context(error)
      }.compact
    end

    def detail(error)
      occurrence = error.recent_occurrence

      summarize(error).merge(
        severity: error.severity,
        source: error.source,
        context: ErrorRedactor.redact(occurrence&.context || {}),
        backtrace: backtrace_lines(occurrence)
      ).compact
    end

    # Surfaces the job class, redacted arguments, and job_id attached by the
    # ApplicationJob hook. Returns nil for request-sourced errors so the caller
    # can tell a job failure from a controller failure.
    def job_context(error)
      context = (error.recent_occurrence&.context || {}).with_indifferent_access
      return unless (job_class = context[:active_job])

      {
        class: job_class,
        arguments: ErrorRedactor.redact(context[:arguments]),
        job_id: context[:job_id]
      }.compact
    end

    def backtrace_lines(occurrence)
      backtrace = occurrence&.parsed_backtrace
      return [] unless backtrace

      lines = backtrace.is_a?(Array) ? backtrace : backtrace.to_s.lines
      lines.map { |line| line.to_s.strip }.first(BACKTRACE_LIMIT)
    end
  end
end
