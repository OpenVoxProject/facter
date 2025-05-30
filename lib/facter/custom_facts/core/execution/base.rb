# frozen_string_literal: true

require_relative 'popen3'

module Facter
  module Core
    module Execution
      class Base
        STDERR_MESSAGE = 'Command %s completed with the following stderr message: %s'
        VALID_OPTIONS = %i[on_fail expand logger timeout].freeze
        DEFAULT_EXECUTION_TIMEOUT = 300
        def initialize
          @log = Log.new(self)
        end

        # This is part of the public API. No race condition can happen
        # here because custom facts are executed sequentially
        def with_env(values)
          old = {}
          values.each do |var, value|
            # save the old value if it exists
            if (old_val = ENV[var])
              old[var] = old_val
            end
            # set the new (temporary) value for the environment variable
            ENV[var] = value
          end
          # execute the caller's block, returning its value
          yield
        # use an ensure block to make absolutely sure we restore the variables
        ensure
          # restore the old values
          values.each_key do |var|
            if old.include?(var)
              ENV[var] = old[var]
            else
              # if there was no old value, delete the key from the current environment variables hash
              ENV.delete(var)
            end
          end
        end

        def execute(command, options = {})
          on_fail, expand, logger, timeout = extract_options(options)

          expanded_command = if !expand && builtin_command?(command) || logger
                               command
                             else
                               expand_command(command)
                             end

          if expanded_command.nil?
            if on_fail == :raise
              raise Facter::Core::Execution::ExecutionFailure.new,
                    "Could not execute '#{command}': command not found"
            end

            return on_fail
          end

          out, = execute_command(expanded_command, on_fail, logger, timeout)
          out
        end

        def execute_command(command, on_fail = nil, logger = nil, timeout = nil)
          timeout ||= DEFAULT_EXECUTION_TIMEOUT
          begin
            # Set LC_ALL and LANG to force i18n to C for the duration of this exec;
            # this ensures that any code that parses the
            # output of the command can expect it to be in a consistent / predictable format / locale
            opts = { 'LC_ALL' => 'C', 'LANG' => 'C' }
            require 'timeout'
            @log.debug("Executing command: #{command}")
            out, stderr = Popen3.popen3e(opts, command.to_s) do |_, stdout, stderr, pid|
              stdout_messages = +''
              stderr_messages = +''
              out_reader = Thread.new { stdout.read }
              err_reader = Thread.new { stderr.read }
              begin
                Timeout.timeout(timeout) do
                  stdout_messages << out_reader.value
                  stderr_messages << err_reader.value
                end
              rescue Timeout::Error
                message = "Timeout encounter after #{timeout}s, killing process with pid: #{pid}"
                Process.kill('KILL', pid)
                on_fail == :raise ? (raise StandardError, message) : @log.debug(message)
              ensure
                out_reader.kill
                err_reader.kill
              end
              [stdout_messages, stderr_messages]
            end
            log_stderr(stderr, command, logger)
          rescue StandardError => e
            message = "Failed while executing '#{command}': #{e.message}"
            if logger
              @log.debug(message)
              return +''
            end

            return on_fail unless on_fail == :raise

            raise Facter::Core::Execution::ExecutionFailure.new, message
          end

          out.force_encoding(Encoding.default_external) unless out.valid_encoding?
          [out.strip, stderr]
        end

        private

        def extract_options(options)
          on_fail = options.fetch(:on_fail, :raise)
          expand = options.fetch(:expand, true)
          logger = options[:logger]
          timeout = (options[:timeout] || options[:time_limit] || options[:limit]).to_i
          timeout = timeout.positive? ? timeout : nil

          extra_keys = options.keys - VALID_OPTIONS
          unless extra_keys.empty?
            @log.warn("Unexpected key passed to Facter::Core::Execution.execute option: #{extra_keys.join(',')}" \
                      " - valid keys: #{VALID_OPTIONS.join(',')}")
          end

          [on_fail, expand, logger, timeout]
        end

        def log_stderr(msg, command, logger)
          return if !msg || msg.empty?

          unless logger
            file_name = command.split('/').last
            logger = Facter::Log.new(file_name)
          end

          logger.debug(format(STDERR_MESSAGE, command, msg.strip))
        end

        def builtin_command?(command)
          output, _status = Open3.capture2("type #{command}")
          /builtin/.match?(output.chomp) || false
        end
      end
    end
  end
end
