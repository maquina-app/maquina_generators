# Single read-only entry point the agent tooling (bin/failures and the MCP
# server) calls into. Keeping the surface here means bin/ and MCP stay thin and
# always return the same shapes.
#
# Read-only by design: nothing here mutates the errors or queue databases.
class FailureTriage
  def self.overview(limit: ErrorsQuery::DEFAULT_LIMIT)
    {
      exceptions: ErrorsQuery.unresolved(limit: limit),
      generated_at: Time.current
    }
  end

  def self.exception(fingerprint)
    ErrorsQuery.find(fingerprint)
  end

  def self.top(limit: ErrorsQuery::TOP_LIMIT)
    {top_exceptions: ErrorsQuery.top(limit: limit)}
  end
end
