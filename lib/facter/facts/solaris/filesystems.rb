# frozen_string_literal: true

module Facts
  module Solaris
    class Filesystems
      FACT_NAME = 'filesystems'

      def call_the_resolver
        fact_value = Facter::Resolvers::Solaris::Filesystems.resolve(:file_systems)
        Facter::ResolvedFact.new(FACT_NAME, fact_value)
      end
    end
  end
end
