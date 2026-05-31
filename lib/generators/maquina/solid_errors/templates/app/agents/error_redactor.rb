# Redacts sensitive values out of error context and job arguments before they
# leave the query layer for an AI agent (or any log). Job arguments and request
# context routinely carry passwords, tokens, and PII; this is the one place that
# stops them from reaching the agent.
#
# Tune SENSITIVE_KEY_PATTERN for your app. Keys that match are masked; everything
# else passes through untouched. Nested hashes and arrays are walked recursively.
class ErrorRedactor
  SENSITIVE_KEY_PATTERN = /pass(word)?|secret|token|api[_-]?key|auth|credential|ssn|card|cvv|email/i
  MASK = "[REDACTED]"

  def self.redact(value)
    new.redact(value)
  end

  def redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, val), acc|
        acc[key] = sensitive?(key) ? MASK : redact(val)
      end
    when Array
      value.map { |item| redact(item) }
    else
      value
    end
  end

  private

  def sensitive?(key)
    SENSITIVE_KEY_PATTERN.match?(key.to_s)
  end
end
