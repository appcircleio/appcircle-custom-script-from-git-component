# frozen_string_literal: true

require 'optparse'
require 'base64'
require 'fileutils'
require 'time'
require 'colored'
require 'English'

def abort_with_message(msg)
  abort msg.red
end

def require_option(options, key)
  value = options[key]
  abort_with_message("Missing required argument: #{key}") if value.nil? || value.empty?
  value
end

def run_command(cmd)
  puts "@@[command] #{cmd}".blue
  system(cmd) || abort_with_message("Command failed: #{cmd}")
end

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb --gitURL=URL --username=USER --token=TOKEN --branch=BRANCH --scriptFile=FILE'

  opts.on('--gitURL=URL', 'Git clone URL')               { |v| options['git_url']     = v }
  opts.on('--username=USER', 'Git username')             { |v| options['username']    = v }
  opts.on('--token=TOKEN', 'Git personal access token')  { |v| options['token']       = v }
  opts.on('--branch=BRANCH', 'Git branch to checkout')    { |v| options['branch']      = v }
  opts.on('--scriptFile=FILE', 'Script file to execute')  { |v| options['script_file'] = v }
end.parse!(ARGV)

%w[git_url username token branch script_file].each do |key|
  options[key] = require_option(options, key)
end

auth_string   = "#{options['username']}:#{options['token']}"
encoded_auth  = Base64.strict_encode64(auth_string)
header_option = "http.extraheader=Authorization: Basic #{encoded_auth}"

timestamp   = Time.now.strftime('%Y%m%d_%H%M%S')
root_folder = "Cloned_Script_#{timestamp}"
FileUtils.mkdir_p(root_folder)

FileUtils.cd(root_folder) do
  run_command("git -c \"#{header_option}\" clone #{options['git_url']}")

  repo_name = File.basename(options['git_url'], '.git')
  Dir.chdir(repo_name) do
    run_command("git checkout #{options['branch']}")

    script = options['script_file']
    abort_with_message("Script file not found: #{script}") unless File.exist?(script)

    case File.extname(script)
    when '.sh'
      FileUtils.chmod('+x', script)
      run_command("./#{script}")
    when '.py'
      run_command("python #{script}")
    when '.rb'
      run_command("ruby #{script}")
    when '.pl'
      run_command("perl #{script}")
    when '.js'
      run_command("node #{script}")
    when '.java'
      run_command("javac #{script}")
      class_name = File.basename(script, '.java')
      run_command("java #{class_name}")
    else
      abort_with_message("Unsupported script type: #{script}")
    end
  end
end

puts 'Done.'.green
