# frozen_string_literal: true

module Facts
  module Linux
    module Os
      class Support
        FACT_NAME = 'os.support'

        def call_the_resolver
          # https://www.freedesktop.org/software/systemd/man/latest/os-release.html#SUPPORT_END=
          support_end = Facter::Resolvers::OsRelease.resolve(:support_end)

          return unless support_end

          [Facter::ResolvedFact.new(FACT_NAME, end: support_end)]
        end
      end
    end
  end
end
