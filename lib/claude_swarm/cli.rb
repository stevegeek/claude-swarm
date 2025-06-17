# frozen_string_literal: true

require "thor"
require "json"
require_relative "configuration"
require_relative "session_path"
require_relative "mcp_generator"
require_relative "orchestrator"
require_relative "claude_mcp_server"

module ClaudeSwarm
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "start [CONFIG_FILE]", "Start a Claude Swarm from configuration file"
    method_option :config, aliases: "-c", type: :string, default: "claude-swarm.yml",
                           desc: "Path to configuration file"
    method_option :vibe, type: :boolean, default: false,
                         desc: "Run with --dangerously-skip-permissions for all instances"
    method_option :prompt, aliases: "-p", type: :string,
                           desc: "Prompt to pass to the main Claude instance (non-interactive mode)"
    method_option :stream_logs, type: :boolean, default: false,
                                desc: "Stream session logs to stdout (only works with -p)"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    method_option :session_id, type: :string,
                               desc: "Resume a previous session by ID or path"
    def start(config_file = nil)
      # Handle session restoration
      if options[:session_id]
        restore_session(options[:session_id])
        return
      end

      config_path = config_file || options[:config]
      unless File.exist?(config_path)
        error "Configuration file not found: #{config_path}"
        exit 1
      end

      say "Starting Claude Swarm from #{config_path}..." unless options[:prompt]

      # Validate stream_logs option
      if options[:stream_logs] && !options[:prompt]
        error "--stream-logs can only be used with -p/--prompt"
        exit 1
      end

      begin
        config = Configuration.new(config_path, base_dir: Dir.pwd)
        generator = McpGenerator.new(config, vibe: options[:vibe])
        orchestrator = Orchestrator.new(config, generator,
                                        vibe: options[:vibe],
                                        prompt: options[:prompt],
                                        stream_logs: options[:stream_logs],
                                        debug: options[:debug])
        orchestrator.start
      rescue Error => e
        error e.message
        exit 1
      rescue StandardError => e
        error "Unexpected error: #{e.message}"
        error e.backtrace.join("\n") if options[:verbose]
        exit 1
      end
    end

    desc "mcp-serve", "Start an MCP server for a Claude instance"
    method_option :name, aliases: "-n", type: :string, required: true,
                         desc: "Instance name"
    method_option :directory, aliases: "-d", type: :string, required: true,
                              desc: "Working directory for the instance"
    method_option :model, aliases: "-m", type: :string, required: true,
                          desc: "Claude model to use (e.g., opus, sonnet)"
    method_option :prompt, aliases: "-p", type: :string,
                           desc: "System prompt for the instance"
    method_option :description, type: :string,
                                desc: "Description of the instance's role"
    method_option :allowed_tools, aliases: "-t", type: :array,
                                  desc: "Allowed tools for the instance"
    method_option :disallowed_tools, type: :array,
                                     desc: "Disallowed tools for the instance"
    method_option :connections, type: :array,
                                desc: "Connections to other instances"
    method_option :mcp_config_path, type: :string,
                                    desc: "Path to MCP configuration file"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    method_option :vibe, type: :boolean, default: false,
                         desc: "Run with --dangerously-skip-permissions"
    method_option :calling_instance, type: :string, required: true,
                                     desc: "Name of the instance that launched this MCP server"
    method_option :calling_instance_id, type: :string,
                                        desc: "Unique ID of the instance that launched this MCP server"
    method_option :instance_id, type: :string,
                                desc: "Unique ID of this instance"
    method_option :claude_session_id, type: :string,
                                      desc: "Claude session ID to resume"
    def mcp_serve
      instance_config = {
        name: options[:name],
        directory: options[:directory],
        model: options[:model],
        prompt: options[:prompt],
        description: options[:description],
        allowed_tools: options[:allowed_tools] || [],
        disallowed_tools: options[:disallowed_tools] || [],
        connections: options[:connections] || [],
        mcp_config_path: options[:mcp_config_path],
        vibe: options[:vibe],
        instance_id: options[:instance_id],
        claude_session_id: options[:claude_session_id]
      }

      begin
        server = ClaudeMcpServer.new(
          instance_config,
          calling_instance: options[:calling_instance],
          calling_instance_id: options[:calling_instance_id]
        )
        server.start
      rescue StandardError => e
        error "Error starting MCP server: #{e.message}"
        error e.backtrace.join("\n") if options[:debug]
        exit 1
      end
    end

    desc "init", "Initialize a new claude-swarm.yml configuration file"
    method_option :force, aliases: "-f", type: :boolean, default: false,
                          desc: "Overwrite existing configuration file"
    def init
      config_path = "claude-swarm.yml"

      if File.exist?(config_path) && !options[:force]
        error "Configuration file already exists: #{config_path}"
        error "Use --force to overwrite"
        exit 1
      end

      template = <<~YAML
        version: 1
        swarm:
          name: "Swarm Name"
          main: lead_developer
          instances:
            lead_developer:
              description: "Lead developer who coordinates the team and makes architectural decisions"
              directory: .
              model: sonnet
              prompt: "You are the lead developer coordinating the team"
              allowed_tools: [Read, Edit, Bash, Write]
              # connections: [frontend_dev, backend_dev]

            # Example instances (uncomment and modify as needed):

            # frontend_dev:
            #   description: "Frontend developer specializing in React and modern web technologies"
            #   directory: ./frontend
            #   model: sonnet
            #   prompt: "You specialize in frontend development with React, TypeScript, and modern web technologies"
            #   allowed_tools: [Read, Edit, Write, "Bash(npm:*)", "Bash(yarn:*)", "Bash(pnpm:*)"]

            # backend_dev:
            #   description: "Backend developer focusing on APIs, databases, and server architecture"
            #   directory: ../other-app/backend
            #   model: sonnet
            #   prompt: "You specialize in backend development, APIs, databases, and server architecture"
            #   allowed_tools: [Read, Edit, Write, Bash]

            # devops_engineer:
            #   description: "DevOps engineer managing infrastructure, CI/CD, and deployments"
            #   directory: .
            #   model: sonnet
            #   prompt: "You specialize in infrastructure, CI/CD, containerization, and deployment"
            #   allowed_tools: [Read, Edit, Write, "Bash(docker:*)", "Bash(kubectl:*)", "Bash(terraform:*)"]

            # qa_engineer:
            #   description: "QA engineer ensuring quality through comprehensive testing"
            #   directory: ./tests
            #   model: sonnet
            #   prompt: "You specialize in testing, quality assurance, and test automation"
            #   allowed_tools: [Read, Edit, Write, Bash]
      YAML

      File.write(config_path, template)
      say "Created #{config_path}", :green
      say "Edit this file to configure your swarm, then run 'claude-swarm' to start"
    end

    desc "version", "Show Claude Swarm version"
    def version
      say "Claude Swarm #{VERSION}"
    end

    desc "list-sessions", "List all available Claude Swarm sessions"
    method_option :limit, aliases: "-l", type: :numeric, default: 10,
                          desc: "Maximum number of sessions to display"
    def list_sessions
      sessions_dir = File.expand_path("~/.claude-swarm/sessions")
      unless Dir.exist?(sessions_dir)
        say "No sessions found", :yellow
        return
      end

      # Find all sessions with MCP configs
      sessions = []
      Dir.glob("#{sessions_dir}/*/*/*.mcp.json").each do |mcp_path|
        session_path = File.dirname(mcp_path)
        session_id = File.basename(session_path)
        project_name = File.basename(File.dirname(session_path))

        # Skip if we've already processed this session
        next if sessions.any? { |s| s[:path] == session_path }

        # Try to load session info
        config_file = File.join(session_path, "config.yml")
        next unless File.exist?(config_file)

        # Load the config to get swarm info
        config_data = YAML.load_file(config_file)
        swarm_name = config_data.dig("swarm", "name") || "Unknown"
        main_instance = config_data.dig("swarm", "main") || "Unknown"

        mcp_files = Dir.glob(File.join(session_path, "*.mcp.json"))

        # Get creation time from directory
        created_at = File.stat(session_path).ctime

        sessions << {
          path: session_path,
          id: session_id,
          project: project_name,
          created_at: created_at,
          main_instance: main_instance,
          instances_count: mcp_files.size,
          swarm_name: swarm_name,
          config_path: config_file
        }
      rescue StandardError
        # Skip invalid manifests
        next
      end

      if sessions.empty?
        say "No sessions found", :yellow
        return
      end

      # Sort by creation time (newest first)
      sessions.sort_by! { |s| -s[:created_at].to_i }
      sessions = sessions.first(options[:limit])

      # Display sessions
      say "\nAvailable sessions (newest first):\n", :bold
      sessions.each do |session|
        say "\n#{session[:project]}/#{session[:id]}", :green
        say "  Created: #{session[:created_at].strftime("%Y-%m-%d %H:%M:%S")}"
        say "  Main: #{session[:main_instance]}"
        say "  Instances: #{session[:instances_count]}"
        say "  Swarm: #{session[:swarm_name]}"
        say "  Config: #{session[:config_path]}", :cyan
      end

      say "\nTo resume a session, run:", :bold
      say "  claude-swarm --session-id <session-id>", :cyan
    end

    desc "tail [SESSION_ID]", "Tail session logs in real-time (defaults to most recent session)"
    method_option :lines, aliases: "-n", type: :numeric, default: 10,
                          desc: "Number of lines to show initially"
    def tail(session_id = nil)
      session_path = nil

      if session_id
        # Find the specific session
        session_path = SessionPath.find_by_id(session_id)
        unless session_path
          error "Session not found: #{session_id}"
          exit 1
        end
      else
        # Find the most recent session
        session_path = SessionPath.find_most_recent
        unless session_path
          error "No sessions found"
          exit 1
        end
      end

      # Look for the session.log file
      log_file = File.join(session_path, "session.log")
      unless File.exist?(log_file)
        error "Log file not found for session"
        exit 1
      end

      say "Tailing log file: #{log_file}", :green
      # Execute the tail command
      exec("tail", "-f", "-n", options[:lines].to_s, log_file)
    end

    desc "tools-mcp", "Start a permission management MCP server for tool access control"
    method_option :allowed_tools, aliases: "-t", type: :string,
                                  desc: "Comma-separated list of allowed tool patterns (supports wildcards)"
    method_option :disallowed_tools, type: :string,
                                     desc: "Comma-separated list of disallowed tool patterns (supports wildcards)"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    def tools_mcp
      server = PermissionMcpServer.new(allowed_tools: options[:allowed_tools], disallowed_tools: options[:disallowed_tools])
      server.start
    rescue StandardError => e
      error "Error starting permission MCP server: #{e.message}"
      error e.backtrace.join("\n") if options[:debug]
      exit 1
    end

    default_task :start

    private

    def error(message)
      say message, :red
    end

    def restore_session(session_id)
      say "Restoring session: #{session_id}", :green

      # Find the session path
      session_path = SessionPath.find_by_id(session_id)
      unless session_path
        error "Session not found: #{session_id}"
        exit 1
      end

      begin
        # Load session info from instance ID in MCP config
        mcp_files = Dir.glob(File.join(session_path, "*.mcp.json"))
        if mcp_files.empty?
          error "No MCP configuration files found in session"
          exit 1
        end

        # Load the configuration from the session directory
        config_file = File.join(session_path, "config.yml")

        unless File.exist?(config_file)
          error "Configuration file not found in session"
          exit 1
        end

        # Change to the original start directory if it exists
        start_dir_file = File.join(session_path, "start_directory")
        if File.exist?(start_dir_file)
          original_dir = File.read(start_dir_file).strip
          if Dir.exist?(original_dir)
            Dir.chdir(original_dir)
            say "Changed to original directory: #{original_dir}", :green unless options[:prompt]
          else
            error "Original directory no longer exists: #{original_dir}"
            exit 1
          end
        end

        config = Configuration.new(config_file, base_dir: Dir.pwd)

        # Create orchestrator with restoration mode
        generator = McpGenerator.new(config, vibe: options[:vibe], restore_session_path: session_path)
        orchestrator = Orchestrator.new(config, generator,
                                        vibe: options[:vibe],
                                        prompt: options[:prompt],
                                        stream_logs: options[:stream_logs],
                                        debug: options[:debug],
                                        restore_session_path: session_path)
        orchestrator.start
      rescue StandardError => e
        error "Failed to restore session: #{e.message}"
        error e.backtrace.join("\n") if options[:debug]
        exit 1
      end
    end
  end
end
