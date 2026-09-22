# One refused request, as Rack::Attack saw it. Rows are written by the
# `rack.attack` subscriber in config/initializers/rack_attack_events.rb and never
# updated — the table is the record of who was throttled or blocked, which
# the middleware otherwise leaves nowhere (it answers ahead of Rails, so the
# request log never sees these, and the cache's counters expire in minutes).
#
# `kind` is decided at write time: a throttle is `throttled`; a scanner path is
# `blocked` until the address's ban is written (Fail2Ban's third strike within
# its window), after which every refused request from it is `banned` — so the
# set of banned addresses is exact, not inferred from counts.
class Security::AbuseEvent < Security::Record
  # Read from here everywhere the retention is stated (config/recurring.yml
  # sweeps `expired`), so the promise and the clock cannot drift.
  RETENTION = 30.days

  KINDS = %w[throttled blocked banned].freeze

  PATH_LIMIT = 1024
  USER_AGENT_LIMIT = 512

  validates :kind, inclusion: {in: KINDS}
  validates :rule, :ip, :request_method, :path, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :within, ->(window) { where(created_at: window.ago..) }
  scope :expired, -> { where(created_at: ...RETENTION.ago) }
  scope :throttled, -> { where(kind: "throttled") }
  scope :blocked, -> { where(kind: %w[blocked banned]) }
  scope :banned, -> { where(kind: "banned") }

  def self.record!(kind:, rule:, ip:, request_method:, path:, host: nil, user_agent: nil)
    create!(kind:, rule:, ip:, request_method:, host:,
      path: path.to_s.truncate(PATH_LIMIT, omission: ""),
      user_agent: user_agent&.truncate(USER_AGENT_LIMIT, omission: ""))
  end
end
