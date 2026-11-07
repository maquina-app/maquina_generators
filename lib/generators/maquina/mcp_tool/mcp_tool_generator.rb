require "rails/generators"

module Maquina
  module Generators
    class McpToolGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      APP_TOOLS = "app/models/mcp/tools/app.rb"
      TOOL_NAME = /\A[a-z][a-z0-9_]*\z/
      ARGUMENT = /\A(?<name>[a-z][a-z0-9_]*):(?<type>[a-z]+)(?:\[(?<values>[^\]]*)\])?(?<optional>\?)?\z/
      ENUM_VALUE = /\A[A-Za-z0-9_.-]+\z/
      TYPES = %w[string integer number boolean enum].freeze
      SAMPLE_VALUES = {"string" => "example", "integer" => 1, "number" => 1.5, "boolean" => true}.freeze
      SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema"

      # The three places in tools/app.rb that maquina:mcp marked for this generator.
      DEFINITIONS_MARKER = /(?<before>[}\[])\n(?<indent> *)(?<marker># maquina:mcp_tool definitions go above this line)$/
      WRITE_TOOLS_LINE = /(?<head># maquina:mcp_tool write tools are listed on the next line\n *WRITE_TOOLS = %w\[)(?<names>[^\]]*)(?<tail>\]\.freeze)$/
      METHODS_MARKER = /^(?<indent> *)# maquina:mcp_tool methods go above this line$/

      argument :tool_name, type: :string, banner: "NAME"
      argument :tool_arguments, type: :array, default: [], banner: "arg:type[?] ..."

      class_option :write, type: :boolean, default: false,
        desc: "The tool changes data: it needs the write scope (WRITE_TOOLS) and has readOnlyHint: false"
      class_option :quiet, type: :boolean, default: false,
        desc: "Suppress the list of items to finish"

      # 1. Tools go into the registry maquina:mcp writes.
      def require_mcp
        return if File.exist?(File.join(destination_root, "app/models/mcp/tools.rb"))

        raise Thor::Error, "maquina:mcp_tool adds a tool to the MCP server. Run `rails g maquina:mcp` first."
      end

      # 2. Everything is checked before anything is written.
      def check_tool
        unless tool_name.match?(TOOL_NAME)
          raise Thor::Error, "#{tool_name.inspect} is not a tool name: use lowercase letters, digits and underscores, starting with a letter."
        end
        if Module.new.respond_to?(tool_name, true)
          raise Thor::Error, "#{tool_name} is already a Ruby method on every module; pick another name."
        end

        @parsed_arguments = tool_arguments.map { |spec| parse_argument(spec) }
        duplicate = @parsed_arguments.map { |arg| arg[:name] }.tally.find { |_, count| count > 1 }
        raise Thor::Error, "#{duplicate.first} is given twice." if duplicate

        owner = registry_owner
        if owner == APP_TOOLS
          @exists = true
          say "#{tool_name} already exists; nothing changed"
        elsif owner
          raise Thor::Error, "#{tool_name} is already a tool in #{owner}. Pick another name."
        end
      end

      # 3. The schema, in DEFINITIONS
      def add_definition
        return if @exists

        content = app_tools_content
        match = DEFINITIONS_MARKER.match(content)
        return @definition_pending = true unless match

        comma = (match[:before] == "}") ? "," : ""
        gsub_file APP_TOOLS, match[0] do
          "#{match[:before]}#{comma}\n#{indent(definition_snippet, match[:indent])}#{match[:indent]}#{match[:marker]}"
        end
      end

      # 4. WRITE_TOOLS, so a read-only token is refused before the tool runs
      def add_write_tool
        return if @exists || !options[:write]

        match = WRITE_TOOLS_LINE.match(app_tools_content)
        return @write_pending = true unless match

        names = match[:names].split
        return if names.include?(tool_name)

        gsub_file APP_TOOLS, match[0] do
          "#{match[:head]}#{(names + [tool_name]).join(" ")}#{match[:tail]}"
        end
      end

      # 5. The method dispatch reaches
      def add_method
        return if @exists

        match = METHODS_MARKER.match(app_tools_content)
        return @method_pending = true unless match

        inject_into_file APP_TOOLS, "#{indent(method_snippet, match[:indent])}\n", before: METHODS_MARKER
      end

      # 6. The tool's test
      def create_test
        return if @exists

        template "test/models/mcp/tools/tool_test.rb.tt", "test/models/mcp/tools/#{tool_name}_test.rb"
      end

      # 7. Items to finish
      def show_items_to_finish
        return if @exists || options[:quiet]

        say ""
        say "#{tool_name} has been added to the MCP server.", :green
        say ""
        say "Items to finish:", :yellow
        say "  1. Write the description of #{tool_name} and of each argument in #{APP_TOOLS}."
        say "     It is what the model reads: plain English, units stated (counts, ISO 8601 UTC times), at most 50 rows."
        say "  2. Write the body of Mcp::Tools::App.#{tool_name}: read through scope"
        say "     (scope.records(:posts), scope.find(:posts, id)) and return a Hash."
        say "  3. Set up the cross-user test in test/models/mcp/tools/#{tool_name}_test.rb:"
        say "     a record owned by users(:mcp_other) must come back not found."
        say ""
        if @definition_pending
          say "Add to DEFINITIONS in #{APP_TOOLS} (the definitions marker is missing):", :yellow
          say indent(definition_snippet, "  ")
        end
        if @write_pending
          say "Add #{tool_name} to WRITE_TOOLS in #{APP_TOOLS} (the write tools marker is missing):", :yellow
          say %(  WRITE_TOOLS = %w[... #{tool_name}].freeze)
          say ""
        end
        if @method_pending
          say "Add to Mcp::Tools::App in #{APP_TOOLS} (the methods marker is missing):", :yellow
          say indent(method_snippet, "  ")
        end
      end

      private

      def parse_argument(spec)
        match = ARGUMENT.match(spec)
        raise Thor::Error, "#{spec.inspect} is not an argument: write name:type, with ? for optional (limit:integer?)." unless match
        if match[:name] == "scope"
          raise Thor::Error, "#{spec}: every tool method already takes scope: (the caller's Mcp::UserScope); name the argument something else."
        end

        type = match[:type]
        unless TYPES.include?(type) && (type == "enum") == !match[:values].nil?
          raise Thor::Error, "#{spec}: the type must be one of string, integer, number, boolean or enum[a,b]."
        end

        values = match[:values].to_s.split(",").map(&:strip)
        if type == "enum" && (values.empty? || !values.all? { |value| value.match?(ENUM_VALUE) })
          raise Thor::Error, "#{spec}: list the enum values, as in status:enum[draft,published]."
        end

        {name: match[:name], type: type, values: values, required: match[:optional].nil?}
      end

      # The registry file that already declares this tool, or nil.
      def registry_owner
        pattern = /\bname: "#{tool_name}"/
        Dir[File.join(destination_root, "app/models/mcp/tools/*.rb")].sort
          .map { |path| path.delete_prefix("#{destination_root}/") }
          .sort_by { |path| (path == APP_TOOLS) ? 0 : 1 }
          .find { |path| File.read(File.join(destination_root, path)).match?(pattern) }
      end

      def app_tools_content
        path = File.join(destination_root, APP_TOOLS)
        File.exist?(path) ? File.read(path) : ""
      end

      def indent(text, prefix)
        text.gsub(/^(?=.)/, prefix)
      end

      def required_arguments
        @parsed_arguments.select { |arg| arg[:required] }
      end

      def definition_snippet
        <<~RUBY
          {
            name: "#{tool_name}",
            description: "TODO: tell the model what #{tool_name} #{options[:write] ? "changes and returns" : "returns"}. " \\
              "Plain English, units stated (counts, ISO 8601 UTC times), lists capped at 50 rows.",
            inputSchema: {
              "$schema": "#{SCHEMA_DIALECT}",
              type: "object",
              properties: #{properties_literal},
              required: [#{required_arguments.map { |arg| %("#{arg[:name]}") }.join(", ")}],
              additionalProperties: false
            },
            annotations: {readOnlyHint: #{!options[:write]}}
          }
        RUBY
      end

      def properties_literal
        return "{}" if @parsed_arguments.empty?

        lines = @parsed_arguments.map { |arg| "  #{arg[:name]}: #{property_literal(arg)}" }
        "{\n#{indent(lines.join(",\n"), "    ")}\n    }"
      end

      def property_literal(arg)
        if arg[:type] == "enum"
          values = arg[:values].map { |value| %("#{value}") }.join(", ")
          %({type: "string", enum: [#{values}], description: "TODO: what #{arg[:name]} selects. One of: #{arg[:values].join(", ")}."})
        else
          %({type: "#{arg[:type]}", description: "TODO: what #{arg[:name]} is, with its unit."})
        end
      end

      def method_snippet
        keywords = ["scope:"] + @parsed_arguments.map { |arg| arg[:required] ? "#{arg[:name]}:" : "#{arg[:name]}: nil" }

        <<~RUBY
          def self.#{tool_name}(#{keywords.join(", ")})
            raise Mcp::ToolError, "#{tool_name} is not implemented yet"
          end
        RUBY
      end

      # Used by the test template.
      def test_class_name
        "McpTool#{tool_name.camelize}Test"
      end

      def sample_value(arg)
        (arg[:type] == "enum") ? arg[:values].first : SAMPLE_VALUES.fetch(arg[:type])
      end

      # A Ruby hash literal of valid arguments, leaving out `except`.
      def arguments_literal(except: nil)
        pairs = required_arguments.reject { |arg| arg[:name] == except }
          .map { |arg| "#{arg[:name]}: #{sample_value(arg).inspect}" }
        pairs.empty? ? "{}" : "{#{pairs.join(", ")}}"
      end
    end
  end
end
