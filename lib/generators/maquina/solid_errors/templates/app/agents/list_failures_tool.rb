# MCP tool: the agent's entry point. Lists unresolved errors (request failures
# and failed jobs alike), most recent first, with redacted job context where
# present.
class ListFailuresTool < MCP::Tool
  tool_name "list_failures"
  description "List unresolved application errors, most recent first. Covers both " \
    "request exceptions and failed background jobs; job failures include their " \
    "class and redacted arguments. Use this first, then get_exception for detail."

  input_schema(
    properties: {
      limit: {type: "integer", description: "Max errors to return (default 25)."}
    }
  )

  def self.call(limit: ErrorsQuery::DEFAULT_LIMIT, server_context: nil)
    payload = FailureTriage.overview(limit: limit)
    MCP::Tool::Response.new([{type: "text", text: JSON.pretty_generate(payload)}])
  end
end
