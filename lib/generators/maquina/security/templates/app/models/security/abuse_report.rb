# What the backstage Security page shows: the last `window` of Rack::Attack refusals,
# summarised to the top `limit` of each thing worth knowing. A briefing, not a
# log viewer — no filters, no pagination; the recent list is the drill-down.
#
# `banned:` answers whether an address is banned right now. It defaults to
# Rack::Attack's own cache read and is a kwarg so a test can hand in a Set.
class Security::AbuseReport
  Address = Data.define(:ip, :count, :rules, :last_seen)
  BannedAddress = Data.define(:ip, :count, :first_banned_at, :banned_now) do
    alias_method :banned_now?, :banned_now
  end
  Path = Data.define(:path, :count, :addresses)
  Host = Data.define(:host, :count)
  Day = Data.define(:date, :throttled, :blocked, :banned) do
    def total = throttled + blocked + banned
  end

  RECENT_LIMIT = 20
  SIGN_IN_RULE = "login/ip"

  attr_reader :window, :limit

  def initialize(window: 7.days, limit: 5, banned: ->(ip) { Rack::Attack.banned?(ip) })
    @window = window
    @limit = limit
    @banned = banned
  end

  def events = Security::AbuseEvent.within(window)

  def empty? = events.none?

  def total = events.count

  def throttled_total = events.throttled.count

  def blocked_total = events.blocked.count

  def addresses_total = events.distinct.count(:ip)

  # Addresses the general and sign-in throttles refused, busiest first.
  def throttled_addresses = addresses(events.throttled)

  # Addresses refused on the sign-in path — the throttle with a security
  # meaning, kept apart so scanner noise never buries it.
  def sign_in_throttles = addresses(events.where(rule: SIGN_IN_RULE))

  # Addresses whose scanner or flood ban is written, by requests refused since.
  def banned_addresses
    events.banned.group(:ip).order(Arel.sql("COUNT(*) DESC, MIN(created_at) DESC")).limit(limit)
      .pluck(:ip, Arel.sql("COUNT(*)"), Arel.sql("MIN(created_at)"))
      .map { |ip, count, first| BannedAddress.new(ip:, count:, first_banned_at: parse_time(first), banned_now: @banned.call(ip)) }
  end

  # What the scanners were after.
  def blocked_paths
    events.blocked.group(:path).order(Arel.sql("COUNT(*) DESC, path ASC")).limit(limit)
      .pluck(:path, Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT ip)"))
      .map { |path, count, addresses| Path.new(path:, count:, addresses:) }
  end

  # Which hostnames took the refusals.
  def targeted_hosts
    events.where.not(host: nil).group(:host).order(Arel.sql("COUNT(*) DESC, host ASC")).limit(limit)
      .pluck(:host, Arel.sql("COUNT(*)"))
      .map { |host, count| Host.new(host:, count:) }
  end

  # One row per day of the window, today last, zeros kept so a spike reads
  # against its neighbours.
  def by_day
    counts = events.group(:kind, Arel.sql("date(created_at)")).count
    days = (window.ago.to_date..Date.current).to_a.last((window / 1.day).ceil)

    days.map do |date|
      key = date.iso8601
      Day.new(date:, throttled: counts.fetch(["throttled", key], 0),
        blocked: counts.fetch(["blocked", key], 0), banned: counts.fetch(["banned", key], 0))
    end
  end

  def recent = events.recent.limit(RECENT_LIMIT)

  private

  # The rules come from a second query rather than GROUP_CONCAT, which only
  # SQLite and MySQL spell that way.
  def addresses(scope)
    rows = scope.group(:ip).order(Arel.sql("COUNT(*) DESC, MAX(created_at) DESC")).limit(limit)
      .pluck(:ip, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
    rules = scope.where(ip: rows.map(&:first)).distinct.order(:rule).pluck(:ip, :rule)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

    rows.map { |ip, count, last| Address.new(ip:, count:, rules: rules.fetch(ip, []), last_seen: parse_time(last)) }
  end

  # SQLite hands an aggregate over a datetime column back as a string.
  def parse_time(value)
    value.is_a?(String) ? Time.zone.parse(value) : value
  end
end
