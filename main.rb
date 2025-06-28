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
  value.nil? || value.strip.empty? ? abort_with_message("Missing #{key}") : value
end

def run_command(cmd)
  puts "@@[command] #{cmd}"
  output = `#{cmd}`
  puts output
  $CHILD_STATUS.success?
end

def determine_root_folder(clone_url, branch, script_path, header_opt)
  return script_path unless script_path.nil? || script_path.strip.empty?

  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  folder = "Cloned_Script_#{timestamp}"
  FileUtils.mkdir_p(folder)
  FileUtils.cd(folder) do
    run_command("git -c \"#{header_opt}\" clone #{clone_url}")
    repo = File.basename(clone_url, '.git')
    FileUtils.cd(repo) { run_command("git checkout #{branch}") }
  end
  folder
end

def prepare_args(raw_params)
  parts = Shellwords.split(raw_params.strip.gsub(',', ' '))
  parts.empty? ? '' : " #{parts.join(' ')}"
end

def execute_script_in(folder, script_file, script_args)
  FileUtils.cd(folder) do
    abort_with_message("Script file not found: #{script_file}") unless File.exist?(script_file)
    ext = File.extname(script_file).downcase
    case ext
    when '.sh', '.shellscript'
      FileUtils.chmod('+x', script_file)
      run_command("./#{script_file}#{script_args}")
    when '.py'
      run_command("python #{script_file}#{script_args}")
    when '.rb'
      run_command("ruby #{script_file}#{script_args}")
    when '.pl'
      run_command("perl #{script_file}#{script_args}")
    when '.js'
      run_command("node #{script_file}#{script_args}")
    when '.java'
      run_command("javac #{script_file}")
      class_name = File.basename(script_file, '.java')
      run_command("java #{class_name}#{script_args}")
    else
      abort_with_message("Unsupported script type: #{script_file}")
    end
  end
end

def write_env_file(env_path, root_folder)
  File.open(env_path, 'a') { |f| f.puts "RUN_SCRIPT_WORKDIR=#{root_folder}" }
end

def main
  cs_git_clone_url   = get_env_variable('CS_GIT_CLONE_URL')
  cs_git_username    = get_env_variable('CS_GIT_USERNAME')
  cs_git_pat         = get_env_variable('CS_GIT_PAT')
  cs_git_branch      = get_env_variable('CS_GIT_BRANCH')
  cs_git_script_file = get_env_variable('CS_GIT_SCRIPT_FILE')
  cs_git_extra_params= ENV['CS_GIT_EXTRA_PARAMS'] || ''
  cs_script_path     = ENV['CS_SCRIPT_PATH']
  ac_env_file_path   = get_env_variable('AC_ENV_FILE_PATH')

  auth         = "#{cs_git_username}:#{cs_git_pat}"
  encoded_auth = Base64.strict_encode64(auth)
  header_opt   = "http.extraheader=Authorization: Basic #{encoded_auth}"

  root_folder = determine_root_folder(cs_git_clone_url, cs_git_branch, cs_script_path, header_opt)
  script_args = prepare_args(cs_git_extra_params)
  execute_script_in(root_folder, cs_git_script_file, script_args)
  write_env_file(ac_env_file_path, root_folder)

  puts 'Done.'.green
end

main
