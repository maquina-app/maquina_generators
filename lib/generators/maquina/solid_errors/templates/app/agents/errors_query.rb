# Read-only queries over the Solid Errors store, shaped for agent consumption.
#
# This layer NEVER writes. Every context hash and job argument list passes
# through ErrorRedactor before leaving this class.
#
# Failed background jobs reach Solid Errors through the Rails error reporter and
# carry the job class/arguments attached by ApplicationJob's around_perform hook,
# so a single read here covers both request and job failures.
#
# Solid Errors keeps no counter columns: an error is a row in solid_errors and
# each time it happened is a row in solid_errors_occurrences. Occurrence counts
# and last-seen times are computed here, one grouped query per page.
class ErrorsQuery
  DEFAULT_LIMIT = 25
  TOP_LIMIT = 10
  BACKTRACE_LIMIT = 50

  class << self
    # Unresolved errors, the most recently seen first.
    def unresolved(limit: DEFAULT_LIMIT)
      last_seen = SolidErrors::Occurrence.where("solid_errors_occurrences.error_id = solid_errors.id").select("MAX(created_at)")

      summaries(
        SolidErrors::Error.unresolved
          .order(Arel.sql("(#{last_seen.to_sql}) DESC"), id: :desc)
          .limit(limit)
      )
    end

    # Unresolved errors with the most occurrences, busiest first.
    def top(limit: TOP_LIMIT)
      ids = SolidErrors::Occurrence.joins(:error).merge(SolidErrors::Error.unresolved)
        .group(:error_id).order(Arel.sql("COUNT(*) DESC"), :error_id)
        .limit(limit).pluck(:error_id)

      summaries(SolidErrors::Error.where(id: ids).index_by(&:id).values_at(*ids).compact)
    end

    def find(fingerprint)
      detail(SolidErrors::Error.find_by!(fingerprint: fingerprint.to_s))
    end

    private

    def summaries(errors)
      errors = errors.to_a
      occurrences = SolidErrors::Occurrence.where(error_id: errors.map(&:id)).group(:error_id)
      counts = occurrences.count
      last_seen = occurrences.maximum(:created_at)
      latest = latest_occurrences(errors)

      errors.map do |error|
        summary(error, occurrences: counts[error.id].to_i, last_seen: last_seen[error.id], latest: latest[error.id])
      end
    end

    def summary(error, occurrences:, last_seen:, latest:)
      {
        fingerprint: error.fingerprint,
        exception: error.exception_class,
        message: error.message,
        occurrences: occurrences,
        last_seen: last_seen,
        job: job_context(latest)
      }.compact
    end

    def detail(error)
      occurrence = error.occurrences.order(created_at: :desc, id: :desc).first

      summaries([error]).first.merge(
        severity: error.severity,
        source: error.source,
        context: ErrorRedactor.redact(occurrence&.context || {}),
        backtrace: backtrace_lines(occurrence)
      ).compact
    end

    # The newest occurrence of each error, keyed by error id: one query for the
    # ids, one for the rows.
    def latest_occurrences(errors)
      ids = SolidErrors::Occurrence.where(error_id: errors.map(&:id)).group(:error_id).maximum(:id).values
      SolidErrors::Occurrence.where(id: ids).index_by(&:error_id)
    end

    # Surfaces the job class, redacted arguments, and job_id attached by the
    # ApplicationJob hook. Returns nil for request-sourced errors so the caller
    # can tell a job failure from a controller failure.
    def job_context(occurrence)
      context = (occurrence&.context || {}).with_indifferent_access
      return unless (job_class = context[:active_job])

      {
        class: job_class,
        arguments: ErrorRedactor.redact(context[:arguments]),
        job_id: context[:job_id]
      }.compact
    end

    # Solid Errors stores the backtrace as text, one frame per line.
    def backtrace_lines(occurrence)
      occurrence&.backtrace.to_s.lines.map(&:strip).reject(&:empty?).first(BACKTRACE_LIMIT)
    end
  end
end
