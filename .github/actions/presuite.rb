# frozen_string_literal: true

require 'open3'
require 'fileutils'

def if_no_env_vars_set_defaults
  ENV['FACTER_ROOT'] = __dir__.gsub('/.github/actions', '') unless ENV['FACTER_ROOT']
  ENV['RELEASE_STREAM'] = 'puppet8' unless ENV['RELEASE_STREAM']
end

def install_facter_acceptance_dependencies
  message('INSTALL FACTER ACCEPTANCE DEPENDENCIES')
  run('bundle install')
end

def initialize_beaker
  beaker_platform_with_options = platform_with_options(beaker_platform)

  message('BEAKER INITIALIZE')
  run("beaker init -h #{beaker_platform_with_options} -o #{File.join('config', 'aio', 'options.rb')}")

  message('BEAKER PROVISION')
  run('beaker provision')
end

def beaker_platform
  {
    'ubuntu-22.04' => 'ubuntu2204-64a',
    'ubuntu-24.04' => 'ubuntu2404-64a',
    'macos-13' => 'osx13-64a',
    'macos-14' => 'osx14-64a',
    'macos-15' => 'osx15-64a',
    'windows-2016' => 'windows2016-64a',
    'windows-2019' => 'windows2019-64a',
    'windows-2022' => 'windows2022-64a',
  }[HOST_PLATFORM]
end

def platform_with_options(platform)
  return "\"#{platform}{hypervisor=none,hostname=localhost,is_cygwin=false}\"" if platform.include? 'windows'

  "#{platform}{hypervisor=none\\,hostname=localhost}"
end

def install_puppet_agent
  message('INSTALL PUPPET AGENT')

  beaker_puppet_root = run('bundle info beaker-puppet --path')

  # Bundler/Rubygems can sometimes give output other than the filepath (deprecation warnings, etc.)
  begin
    if File.exist?(beaker_puppet_root.chomp)
      presuite_file_path = File.join(beaker_puppet_root.chomp, 'setup', 'aio', '010_Install_Puppet_Agent.rb')

      run("beaker exec pre-suite --pre-suite #{presuite_file_path} --preserve-state", './', env_path_var)
    else
      exit
    end
  rescue SystemExit
    puts "`bundle info beaker-puppet --path` produced unexpected output, please address this."
  end
end

def puppet_puppet_bin_dir
  return '/opt/puppetlabs/puppet/bin' unless HOST_PLATFORM.include? 'windows'

  'C:\\Program Files\\Puppet Labs\\Puppet\\puppet\\bin'
end

def puppet_bin_dir
  return '/opt/puppetlabs/puppet/bin' unless HOST_PLATFORM.include? 'windows'

  'C:\\Program Files\\Puppet Labs\\Puppet\\bin'
end

def puppet_ruby
  return '/opt/puppetlabs/puppet/bin/ruby' unless HOST_PLATFORM.include? 'windows'

  'C:\\Program Files\\Puppet Labs\\Puppet\\puppet\\bin\\ruby.exe'
end

def facter_lib_path
  return '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/facter' unless HOST_PLATFORM.include? 'windows'

  'C:\\Program Files\\Puppet Labs\\Puppet\\puppet\\lib\\ruby\\vendor_ruby\\facter'
end

def env_path_var
  HOST_PLATFORM.include?('windows') ? { 'PATH' => "#{puppet_bin_dir};#{ENV['PATH']}" } : {}
end

def install_facter
  message('OVERWRITE FACTER FROM PUPPET AGENT')

  # clean facter directory
  FileUtils.rm_r(facter_lib_path)
  FileUtils.mkdir(facter_lib_path)

  Dir.chdir('../') do
    run("\'#{puppet_ruby}\' install.rb --bindir=\'#{puppet_puppet_bin_dir}\' " \
    "--sitelibdir=\'#{facter_lib_path.gsub('facter', '')}\'")
  end
end

def run_acceptance_tests
  message('RUN ACCEPTANCE TESTS')

  run('beaker exec tests --test-tag-exclude=server,facter_3 --test-tag-or=risk:high,audit:high', './', env_path_var)
end

def message(message)
  message_length = message.length
  total_length = 130
  lines_length = (total_length - message_length) / 2
  result = ('-' * lines_length + ' ' + message + ' ' + '-' * lines_length)[0, total_length]
  puts "\n\n#{result}\n\n"
end

def run(command, dir = './', env = {})
  puts command
  output = ''
  Open3.popen2e(env, command, chdir: dir) do |_stdin, stdout_and_err, wait_thr|
    stdout_and_err.each do |line|
      puts line
      output += line
    end
    exit_status = wait_thr.value.exitstatus
    exit(exit_status) if exit_status != 0
  end
  output
end

def verify_facter_standalone_exits_0
  Dir.chdir(ENV['FACTER_ROOT']) do
    # `documentation` group contains ronn and hpricot
    # both gems are ancient, dead upstream, don't compile on modern rubies
    # and are only required for building manpages
    run('bundle install --without development:documentation')
    run('bundle exec facter')
  end
end

ENV['DEBIAN_DISABLE_RUBYGEMS_INTEGRATION'] = 'no_warnings'
if_no_env_vars_set_defaults
ACCEPTANCE_PATH = File.join(ENV['FACTER_ROOT'], 'acceptance')
HOST_PLATFORM = ARGV[0]

verify_facter_standalone_exits_0

Dir.chdir(ACCEPTANCE_PATH) do
  install_facter_acceptance_dependencies
  initialize_beaker
  install_puppet_agent
  install_facter
  run_acceptance_tests
end
