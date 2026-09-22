# frozen_string_literal: true

# Records every refused request as a Security::AbuseEvent for the backstage
# Security page. Rack::Attack answers before Rails, so this subscriber and the
# [ATTACK] line in config/initializers/rack_attack.rb are the only trace a
# refusal leaves. Safelist matches stay silent.
#
# `kind` is decided here: a throttle is `throttled`; a blocklist match is
# `banned` once Rack::Attack.banned? says the address's ban is written, and
# `blocked` until then.
#
# The record is best effort: Rack::Attack runs inside ActionDispatch::Executor
# so the connection is returned at request end, but a locked database must
# never turn a 403 into a 500.
ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  match_type = req.env["rack.attack.match_type"]
  next unless %i[blocklist throttle].include?(match_type)

  kind = if match_type == :throttle
    "throttled"
  elsif Rack::Attack.banned?(req.ip)
    "banned"
  else
    "blocked"
  end

  begin
    Security::AbuseEvent.record!(kind:, rule: req.env["rack.attack.matched"], ip: req.ip,
      request_method: req.request_method, path: req.path, host: req.host, user_agent: req.user_agent)
  rescue => error
    Rails.logger.error "[ATTACK] not recorded: #{error.class}: #{error.message}"
  end
end
