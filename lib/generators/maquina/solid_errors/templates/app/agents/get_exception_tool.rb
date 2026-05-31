# MCP tool: full detail for one error by fingerprint — backtrace, redacted
# context, and (for job failures) the replayable arguments the agent can turn
# into a regression test.
class GetExceptionTool < MCP::Tool
  tool_name "get_exception"
  description "Fetch full detail for one error by fingerprint: backtrace, redacted " \
    "context, and — for background-job failures — the redacted arguments that " \
    "triggered it. Get the fingerprint from list_failures or top_exceptions."

  input_schema(
    properties: {
      fingerprint: {type: "string", description: "Error fingerprint from list_failures."}
    },
    required: ["fingerprint"]
  )

  def self.call(fingerprint:, server_context: nil)
    payload = FailureTriage.exception(fingerprint)
    MCP::Tool::Response.new([{type: "text", text: JSON.pretty_generate(payload)}])
  rescue ActiveRecord::RecordNotFound
    MCP::Tool::Response.new(
      [{type: "text", text: JSON.pretty_generate(error: "No unresolved error found for fingerprint #{fingerprint}")}],
      error: true
    )
  end
end
