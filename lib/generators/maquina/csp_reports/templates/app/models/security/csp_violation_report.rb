# What the Security page shows about Content Security Policy: the last `window`
# of reported violations, grouped by what was blocked, where and why.
class Security::CspViolationReport
  Group = Data.define(:effective_directive, :blocked_uri, :document_uri, :count, :last_seen)

  attr_reader :window, :limit

  def initialize(window: 7.days, limit: 10)
    @window = window
    @limit = limit
  end

  def violations = Security::CspViolation.within(window)

  def empty? = violations.none?

  def total = violations.count

  # The same blocked resource on the same page under the same directive, most
  # frequent first — one row per thing to fix, however many readers hit it.
  def top
    violations.group(:effective_directive, :blocked_uri, :document_uri)
      .order(Arel.sql("COUNT(*) DESC, MAX(created_at) DESC")).limit(limit)
      .pluck(:effective_directive, :blocked_uri, :document_uri, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
      .map do |directive, blocked, document, count, last|
        Group.new(effective_directive: directive, blocked_uri: blocked, document_uri: document,
          count:, last_seen: last.is_a?(String) ? ActiveSupport::TimeZone["UTC"].parse(last) : last)
      end
  end
end
