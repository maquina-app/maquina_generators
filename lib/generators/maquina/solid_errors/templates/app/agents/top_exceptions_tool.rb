# MCP tool: the most frequent unresolved errors by occurrence count — lets the
# agent prioritize what is failing most, not just what failed most recently.
class TopExceptionsTool < MCP::Tool
  tool_name "top_exceptions"
  description "List the most frequent unresolved errors by occurrence count, to " \
    "prioritize what is failing most often rather than most recently."

  input_schema(
    properties: {
      limit: {type: "integer", description: "Max errors to return (default 10)."}
    }
  )

  def self.call(limit: ErrorsQuery::TOP_LIMIT, server_context: nil)
    payload = FailureTriage.top(limit: limit)
    MCP::Tool::Response.new([{type: "text", text: JSON.pretty_generate(payload)}])
  end
end
