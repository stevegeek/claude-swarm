# frozen_string_literal: true

require "fast_mcp_annotations"
require "json"
require_relative "claude_code_executor"
require_relative "task_tool"
require_relative "session_info_tool"
require_relative "reset_session_tool"
require_relative "process_tracker"

module ClaudeSwarm
  class ClaudeMcpServer
    # Class variables to share state with tool classes
    class << self
      attr_accessor :executor, :instance_config, :logger, :session_path, :calling_instance, :calling_instance_id
    end

    def initialize(instance_config, calling_instance:, calling_instance_id: nil)
      @instance_config = instance_config
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @executor = ClaudeCodeExecutor.new(
        working_directory: instance_config[:directory],
        model: instance_config[:model],
        mcp_config: instance_config[:mcp_config_path],
        vibe: instance_config[:vibe],
        instance_name: instance_config[:name],
        instance_id: instance_config[:instance_id],
        calling_instance: calling_instance,
        calling_instance_id: calling_instance_id,
        claude_session_id: instance_config[:claude_session_id],
        additional_directories: instance_config[:directories][1..] || []
      )

      # Set class variables so tools can access them
      self.class.executor = @executor
      self.class.instance_config = @instance_config
      self.class.logger = @executor.logger
      self.class.session_path = @executor.session_path
      self.class.calling_instance = @calling_instance
      self.class.calling_instance_id = @calling_instance_id
    end

    def start
      # Track this process
      if @executor.session_path && File.exist?(@executor.session_path)
        tracker = ProcessTracker.new(@executor.session_path)
        tracker.track_pid(Process.pid, "mcp_#{@instance_config[:name]}")
      end

      server = FastMcp::Server.new(
        name: @instance_config[:name],
        version: "1.0.0"
      )

      # Set dynamic description for TaskTool based on instance config
      if @instance_config[:description]
        TaskTool.description "Execute a task using Agent #{@instance_config[:name]}. #{@instance_config[:description]}"
      else
        TaskTool.description "Execute a task using Agent #{@instance_config[:name]}"
      end

      # Register tool classes (not instances)
      server.register_tool(TaskTool)
      server.register_tool(SessionInfoTool)
      server.register_tool(ResetSessionTool)

      # Start the stdio server
      server.start
    end
  end
end
