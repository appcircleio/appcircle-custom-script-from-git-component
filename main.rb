#!/usr/bin/env ruby
require 'base64'
require 'fileutils'
require 'time'
require 'colored'
require 'English'
require 'shellwords'

def abort_with_message(msg)
  abort msg.red
end

def get_env_variable(key)
  value = ENV[key]
  value.nil? || value.strip.empty? ? nil : value
end

def run_command(cmd)
  puts "@@[command] #{cmd}"
  output = `#{cmd}`
  puts output
  $CHILD_STATUS.success?
end

cs_git_clone_url   = get_env_variable('CS_GIT_CLONE_URL')   || abort_with_message('Missing CS_GIT_CLONE_URL')
cs_git_username    = get_env_variable('CS_GIT_USERNAME')    || abort_with_message('Missing CS_GIT_USERNAME')
cs_git_pat         = get_env_variable('CS_GIT_PAT')         || abort_with_message('Missing CS_GIT_PAT')
cs_git_branch      = get_env_variable('CS_GIT_BRANCH')      || abort_with_message('Missing CS_GIT_BRANCH')
cs_git_script_file = get_env_variable('CS_GIT_SCRIPT_FILE') || abort_with_message('Missing CS_GIT_SCRIPT_FILE')
cs_git_extra_params= ENV['CS_GIT_EXTRA_PARAMS'] || ''
cs_script_path     = ENV['CS_SCRIPT_PATH']

auth         = "#{cs_git_username}:#{cs_git_pat}"
encoded_auth = Base64.strict_encode64(auth)
header_opt   = "http.extraheader=Authorization: Basic #{encoded_auth}"

if cs_script_path && !cs_script_path.strip.empty?
  root_folder = cs_script_path
else
  timestamp   = Time.now.strftime('%Y%m%d_%H%M%S')
  root_folder = "Cloned_Script_#{timestamp}"
  FileUtils.mkdir_p(root_folder)
  FileUtils.cd(root_folder) do
    run_command("git -c \"#{header_opt}\" clone #{cs_git_clone_url}")
    repo_name = File.basename(cs_git_clone_url, '.git')
    FileUtils.cd(repo_name) do
      run_command("git checkout #{cs_git_branch}")
    end
  end
end

FileUtils.cd(root_folder) do
  script = cs_git_script_file
  abort_with_message("Script file not found: #{script}") unless File.exist?(script)

  args_array = Shellwords.split(cs_git_extra_params.strip.gsub(',', ' '))
  script_args = args_array.empty? ? '' : " #{args_array.join(' ')}"

  case File.extname(script).downcase
  when '.sh'
    FileUtils.chmod('+x', script)
    run_command("./#{script}#{script_args}")
  when '.py'
    run_command("python #{script}#{script_args}")
  when '.rb'
    run_command("ruby #{script}#{script_args}")
  when '.pl'
    run_command("perl #{script}#{script_args}")
  when '.js'
    run_command("node #{script}#{script_args}")
  when '.java'
    run_command("javac #{script}")
    class_name = File.basename(script, '.java')
    run_command("java #{class_name}#{script_args}")
  else
    abort_with_message("Unsupported script type: #{script}")
  end
end

puts 'Done.'.green
