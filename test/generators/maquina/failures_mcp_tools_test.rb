require "test_helper"
require "mcp"

# Loads the generated MCP tool templates against the real `mcp` gem to confirm
# our DSL usage (tool_name/description/input_schema) and server assembly stay
# valid as the gem evolves. These are the verbatim files copied into host apps.
class FailuresMcpToolsTest < Minitest::Test
  AGENTS_DIR = File.expand_path(
    "../../../lib/generators/maquina/solid_errors/templates/app/agents",
    __dir__
  )

  TOOLS = %w[list_failures_tool get_exception_tool top_exceptions_tool].freeze

  def setup
    TOOLS.each { |file| require File.join(AGENTS_DIR, "#{file}.rb") }
  end

  def test_tools_subclass_mcp_tool_with_snake_case_names
    assert_operator ListFailuresTool, :<, MCP::Tool
    assert_operator GetExceptionTool, :<, MCP::Tool
    assert_operator TopExceptionsTool, :<, MCP::Tool

    assert_equal "list_failures", ListFailuresTool.tool_name
    assert_equal "get_exception", GetExceptionTool.tool_name
    assert_equal "top_exceptions", TopExceptionsTool.tool_name
  end

  def test_server_assembles_with_all_three_tools
    server = MCP::Server.new(
      name: "failures",
      tools: [ListFailuresTool, GetExceptionTool, TopExceptionsTool]
    )

    assert_instance_of MCP::Server, server
  end
end
