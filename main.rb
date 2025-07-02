#!/usr/bin/env ruby
require 'base64'
require 'fileutils'
require 'time'
require 'colored'
require 'English'
require 'shellwords'

def abort_with_message(msg)
  puts "@@[error] #{msg}"
  exit 0
end

def env_has_key(key)
  value = ENV[key]
  value.nil? || value.strip.empty? ? abort_with_message("Missing #{key}") : value
end
def get_env_variable(key)
  value = ENV[key]
  value && !value.strip.empty? ? value : nil
end

def validate_input_script_folder(input_path, script_file)
  file_path = File.join(input_path, script_file)
  abort_with_message("Script file not found at AC_SCRIPT_REPO_DIR: #{file_path}") unless File.exist?(file_path)
end

def runCommand(command)
  puts "@@[command] #{command}"
  return if system(command)
  exit $?.exitstatus
end

def get_path_cloned_repo(clone_url, branch, extra_header)
  abort_with_message('Missing AC_SCRIPT_REPO_CLONE_URL or AC_SCRIPT_GIT_BRANCH') if clone_url.nil? || clone_url.strip.empty? || branch.nil? || branch.strip.empty?
  root_folder = "Cloned_Script_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
  FileUtils.mkdir_p(root_folder)
  repo_name = File.basename(clone_url, '.git')
  repo_folder_path = File.join(root_folder, repo_name)
  FileUtils.cd(root_folder) do
    abort_with_message("Git clone failed: #{clone_url}") unless run_command("git -c \"#{extra_header}\" clone #{clone_url}")
  end
  repo_folder_path
end

def prepare_args(raw_params)
  parts = Shellwords.split(raw_params.to_s.gsub(',', ' '))
  parts.empty? ? '' : " #{parts.join(' ')}"
end

def execute_script_in(folder, script_file, script_args)
  FileUtils.cd(folder) do
    abort_with_message("Git checkout failed: #{branch}") unless run_command("git checkout #{branch}")
    abort_with_message("Script file not found: #{script_file}") unless File.exist?(script_file)
    extname = File.extname(script_file).downcase
    case extname
    when '.sh'
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

def write_env_file(output_path,root_folder)
  unless ENV['AC_ENV_FILE_PATH'].include?("#{output_path}=")
    File.open(ENV['AC_ENV_FILE_PATH'], 'a') do |f|
      f.puts "#{output_path}=#{root_folder}"
    end
  end
end

def set_the_authentication(username, pat)
  abort_with_message('Missing AC_SCRIPT_GIT_USERNAME or AC_SCRIPT_GIT_PAT') if username.nil? || username.strip.empty? || pat.nil? || pat.strip.empty?
  auth = "#{username}:#{pat}"
  encoded = Base64.strict_encode64(auth)
  "http.extraheader=Authorization: Basic #{encoded}"
end

def main
  ac_git_script_file   = env_has_key('AC_SCRIPT_FILENAME')
  ac_git_input_path    = get_env_variable('AC_SCRIPT_REPO_DIR')
  ac_git_clone_url     = get_env_variable('AC_SCRIPT_REPO_CLONE_URL')
  ac_git_username      = get_env_variable('AC_SCRIPT_GIT_USERNAME')
  ac_git_pat           = get_env_variable('AC_SCRIPT_GIT_PAT')
  ac_git_branch        = get_env_variable('AC_SCRIPT_GIT_BRANCH')
  ac_git_extra_params  = get_env_variable('AC_SCRIPT_EXTRA_PARAMETERS')
  ac_git_output_path   = get_env_variable('AC_SCRIPT_REPO_OUTPUT_DIR')

  if ac_git_username && ac_git_pat && ac_git_clone_url
    extra_header = set_the_authentication(ac_git_username, ac_git_pat)
    root_folder = get_path_cloned_repo(ac_git_clone_url, ac_git_branch, extra_header)
  else
    validate_input_script_folder(ac_git_input_path, ac_git_script_file)
    root_folder = ac_git_input_path
  end

  script_args = prepare_args(ac_git_extra_params)
  execute_script_in(root_folder, ac_git_script_file, script_args)

  write_env_file(ac_git_output_path,root_folder)

  puts 'Done.'.green
end

main
