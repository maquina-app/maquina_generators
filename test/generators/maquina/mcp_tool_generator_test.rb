require "test_helper"
require "generators/maquina/mcp_tool/mcp_tool_generator"

class Maquina::Generators::McpToolGeneratorTest < Rails::Generators::TestCase
  tests Maquina::Generators::McpToolGenerator
  destination File.expand_path("../../tmp", __dir__)

  MCP_TEMPLATES = File.expand_path("../../../lib/generators/maquina/mcp/templates", __dir__)
  APP_TOOLS = "app/models/mcp/tools/app.rb"

  setup do
    prepare_destination
    write "app/models/mcp/tools.rb", "module Mcp\n  module Tools\n  end\nend\n"
    # tools/app.rb as maquina:mcp writes it.
    write APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
  end

  test "refuses to run without maquina:mcp" do
    File.delete(File.join(destination_root, "app/models/mcp/tools.rb"))

    output = capture(:stderr) { run_generator %w[list_posts] }

    assert_match(/Run `rails g maquina:mcp` first/, output)
    assert_no_file "test/models/mcp/tools/list_posts_test.rb"
  end

  test "refuses a name that is not a tool name" do
    %w[ListPosts list-posts 1posts].each do |name|
      output = capture(:stderr) { run_generator [name] }

      assert_match(/is not a tool name/, output, name)
    end
    assert_file APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
  end

  test "refuses a name every module already answers to" do
    output = capture(:stderr) { run_generator %w[name] }

    assert_match(/name is already a Ruby method/, output)
  end

  test "refuses an unknown type and names the allowed ones" do
    output = capture(:stderr) { run_generator %w[list_posts since:date] }

    assert_match(/string, integer, number, boolean or enum\[a,b\]/, output)
    assert_file APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
    assert_no_file "test/models/mcp/tools/list_posts_test.rb"
  end

  test "refuses an enum without values, values on another type, a repeated argument and scope" do
    {
      %w[list_posts status:enum[]] => /list the enum values/,
      %w[list_posts status:string[a,b]] => /the type must be one of/,
      %w[list_posts limit limit:integer] => /is not an argument/,
      %w[list_posts limit:integer limit:integer?] => /limit is given twice/,
      %w[list_posts scope:string?] => /every tool method already takes scope: \(the caller's Mcp::UserScope\)/
    }.each do |args, message|
      assert_match(message, capture(:stderr) { run_generator args }, args.join(" "))
    end
    assert_file APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
  end

  test "refuses a name another registry file declares" do
    write "app/models/mcp/tools/solid_errors.rb", %(module Mcp\n  module Tools\n    module SolidErrors\n      DEFINITIONS = [{name: "list_failures"}].freeze\n    end\n  end\nend\n)

    output = capture(:stderr) { run_generator %w[list_failures] }

    assert_match(/list_failures is already a tool in app\/models\/mcp\/tools\/solid_errors\.rb/, output)
    assert_file APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
  end

  test "adds the schema, the method and the test" do
    run_generator ["list_posts", "status:enum[draft,published]?", "limit:integer?", "query:string", "ratio:number?", "archived:boolean"]

    tools = load_app_tools
    assert_equal %w[whoami list_posts], tools::DEFINITIONS.map { |definition| definition[:name] }
    definition = tools::DEFINITIONS.last
    assert_equal({
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      type: "object",
      properties: {
        status: {type: "string", enum: %w[draft published], description: "TODO: what status selects. One of: draft, published."},
        limit: {type: "integer", description: "TODO: what limit is, with its unit."},
        query: {type: "string", description: "TODO: what query is, with its unit."},
        ratio: {type: "number", description: "TODO: what ratio is, with its unit."},
        archived: {type: "boolean", description: "TODO: what archived is, with its unit."}
      },
      required: %w[query archived],
      additionalProperties: false
    }, definition[:inputSchema])
    assert_equal({readOnlyHint: true}, definition[:annotations])
    assert_match(/\ATODO: tell the model what list_posts returns/, definition[:description])
    assert_equal [], tools::WRITE_TOOLS

    parameters = tools.method(:list_posts).parameters.to_h { |kind, name| [name, kind] }
    assert_equal({scope: :keyreq, status: :key, limit: :key, query: :keyreq, ratio: :key, archived: :keyreq}, parameters)
    error = assert_raises(StandardError) { tools.list_posts(scope: nil, query: "a", archived: true) }
    assert_equal "ToolError", error.class.name.demodulize
    assert_equal "list_posts is not implemented yet", error.message

    assert_file APP_TOOLS do |content|
      assert_operator content.index("def self.list_posts"), :>, content.index("def self.whoami")
      assert_operator content.index("def self.list_posts"), :<, content.index("# maquina:mcp_tool methods go above this line")
      assert_match(/^        # maquina:mcp_tool definitions go above this line$/, content)
    end

    assert_file "test/models/mcp/tools/list_posts_test.rb" do |content|
      assert_match(/class McpToolListPostsTest < ActionDispatch::IntegrationTest/, content)
      assert_match(/test "list_posts is listed for a read token"/, content)
      assert_match(/test "a call without query is invalid params"/, content)
      assert_match(/arguments: \{archived: true\}/, content)
      assert_match(/assert_equal\(-32602, /, content)
      assert_match(/skip "TODO: create a record owned by users\(:mcp_other\)/, content)
      assert_no_match(/insufficient_scope/, content)
    end
  end

  test "a tool without required arguments tests an undeclared one instead" do
    run_generator %w[list_posts limit:integer?]

    assert_file "test/models/mcp/tools/list_posts_test.rb" do |content|
      assert_match(/test "a call with an argument the schema does not declare is invalid params"/, content)
      assert_match(/arguments: \{undeclared: 1\}/, content)
    end
  end

  test "write adds the tool to WRITE_TOOLS and tests the read-only refusal" do
    run_generator %w[publish_post id:integer --write]
    run_generator %w[archive_post id:integer --write]

    tools = load_app_tools
    assert_equal %w[publish_post archive_post], tools::WRITE_TOOLS
    assert_equal [{readOnlyHint: false}], tools::DEFINITIONS.drop(1).map { |definition| definition[:annotations] }.uniq
    assert_file APP_TOOLS, /^      WRITE_TOOLS = %w\[publish_post archive_post\]\.freeze$/

    assert_file "test/models/mcp/tools/publish_post_test.rb" do |content|
      assert_match(/test "a read-only token cannot call publish_post"/, content)
      assert_match(/arguments: \{id: 1\}\}\}, token: @token\)\n\n    assert_response :forbidden/, content)
      assert_match(/error="insufficient_scope"/, content)
      # The missing-argument call needs a write token to get past the scope check.
      assert_match(/arguments: \{\}\}\}, token: oauth_token_for\(users\(:mcp_member\), scope: "read write"\)\)/, content)
    end
  end

  test "adds to an emptied DEFINITIONS without a stray comma" do
    write APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS)).sub(/^        \{\n.*?^        \}\n/m, "")

    run_generator %w[list_posts]

    assert_equal %w[list_posts], load_app_tools::DEFINITIONS.map { |definition| definition[:name] }
    assert_file APP_TOOLS, /DEFINITIONS = \[\n        \{\n          name: "list_posts"/
  end

  test "running twice changes nothing and says so" do
    run_generator %w[list_posts limit:integer? --write]
    before = snapshot

    output = run_generator %w[list_posts limit:integer? --write]

    assert_match(/list_posts already exists; nothing changed/, output)
    assert_no_match(/Items to finish/, output)
    assert_equal before, snapshot
  end

  test "an existing tool name is left alone" do
    output = run_generator %w[whoami]

    assert_match(/whoami already exists; nothing changed/, output)
    assert_file APP_TOOLS, File.read(File.join(MCP_TEMPLATES, APP_TOOLS))
    assert_no_file "test/models/mcp/tools/whoami_test.rb"
  end

  test "lists the items to finish" do
    output = run_generator %w[list_posts]

    assert_match(/Items to finish:/, output)
    assert_match(/Write the description of list_posts/, output)
    assert_match(/Write the body of Mcp::Tools::App\.list_posts/, output)
    assert_match(/cross-user test in test\/models\/mcp\/tools\/list_posts_test\.rb/, output)
  end

  test "prints what it could not place when the markers are gone" do
    custom = "module Mcp\n  module Tools\n    module App\n    end\n  end\nend\n"
    write APP_TOOLS, custom

    output = run_generator %w[publish_post id:integer --write]

    assert_file APP_TOOLS, custom
    assert_match(/Add to DEFINITIONS in app\/models\/mcp\/tools\/app\.rb.*name: "publish_post"/m, output)
    assert_match(/Add publish_post to WRITE_TOOLS/, output)
    assert_match(/Add to Mcp::Tools::App in app\/models\/mcp\/tools\/app\.rb.*def self\.publish_post\(scope:, id:\)/m, output)
  end

  test "the generated files parse" do
    run_generator ["list_posts", "status:enum[draft,published]?", "id:integer", "--write"]

    [APP_TOOLS, "test/models/mcp/tools/list_posts_test.rb"].each do |path|
      assert RubyVM::InstructionSequence.compile(File.read(File.join(destination_root, path)), path)
    end
  end

  test "quiet hides the items to finish" do
    output = run_generator %w[list_posts --quiet]

    assert_no_match(/Items to finish/, output)
  end

  private

  # Mcp::Tools::App from the generated file, in a sandbox.
  def load_app_tools
    sandbox = Module.new
    sandbox.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      module Mcp
        PROTOCOL_VERSION = "2026-07-28"
        SERVER_VERSION = "0.1.0"
        FLAG = nil
        ToolError = Class.new(StandardError)
      end
    RUBY
    sandbox.module_eval(File.read(File.join(destination_root, APP_TOOLS)), APP_TOOLS)
    sandbox::Mcp::Tools::App
  end

  def snapshot
    Dir[File.join(destination_root, "**/*")].select { |path| File.file?(path) }.sort
      .to_h { |path| [path, File.read(path)] }
  end

  def write(path, content)
    full_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end
end
