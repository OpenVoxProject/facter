# frozen_string_literal: true

module Facter
  module Resolvers
    module Solaris
      class Filesystems < BaseResolver
        init_resolver

        class << self
          private

          def post_resolve(fact_name, _options)
            @fact_list.fetch(fact_name) { read_sysdef_file(fact_name) }
          end

          def read_sysdef_file(fact_name)
            return unless File.executable?('/usr/sbin/sysdef')

            file_content = Facter::Core::Execution.execute('/usr/sbin/sysdef', logger: log)
            files = file_content.split("\n").map do |line|
              line.split('/').last if /^fs\.*/.match?(line)
            end

            @fact_list[:file_systems] = files.compact.sort.join(',')
            @fact_list[fact_name]
          end
        end
      end
    end
  end
end
