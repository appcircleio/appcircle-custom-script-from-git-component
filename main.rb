#!/usr/bin/env ruby
require 'base64'
require 'fileutils'
require 'time'
require 'open3'
require 'colored'
require 'English'
require 'shellwords'

def abort_with_message(msg)
  abort "@@[error] #{msg}"
end

def env_has_key(key)
  value = ENV[key]
  value.nil? || value.strip.empty? ? abort_with_message("Missing #{key}") : value
end

def get_env_variable(key)
  value = ENV[key]
  value && !value.strip.empty? ? value : nil
end

def param_checker(*params)
  params.all? { |p| !p.to_s.strip.empty? }
end

def validate_input_script_folder(input_path, script_file)
  file_path = File.join(input_path, script_file)
  abort_with_message("Script file or repository directory not found at AC_SCRIPT_REPO_DIR: #{file_path}") unless File.exist?(file_path)
end

def run_command(cmd)
  masked = cmd.gsub(/(Authorization:\s*\w+\s+)\S+/,'\1********')
  puts "@@[command] #{masked}"
  stdout, stderr, status = Open3.capture3(cmd)
  puts stdout unless stdout.empty?
  unless status.success?
    raise "Command failed (#{status.exitstatus}):\n#{stderr}"
  end
  true
end
def get_path_clone_repo(clone_url, extra_header = nil)
  root = "Cloned_Script_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
  FileUtils.mkdir_p(root)
  repo = File.basename(clone_url, '.git')
  path = File.join(root, repo)
  FileUtils.cd(root) do
    cmd = extra_header ? %Q[git -c "#{extra_header}" clone #{clone_url}] : "git clone #{clone_url}"
    abort("Error: Cloning failed") unless run_command(cmd)
  end
  path
end

def prepare_args(raw_params)
  parts = Shellwords.split(raw_params.to_s.gsub(',', ' '))
  parts.empty? ? '' : " #{parts.join(' ')}"
end

def execute_script_in(folder, script_file, branch, script_args)
  FileUtils.cd(folder) do
    if branch.nil? || branch.strip.empty?
      branch = "main"
    end
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

def write_env_file(root_folder)
  File.open(ENV['AC_ENV_FILE_PATH'], 'a') do |f|
    f.puts "AC_SCRIPT_REPO_OUTPUT_DIR=#{root_folder}"
  end
end

def set_the_authentication(username, pat)
  auth = "#{username}:#{pat}"
  return nil if auth.to_s.strip.empty?
  encoded = Base64.strict_encode64(auth)
  "http.extraheader=Authorization: Basic #{encoded}"
end

def main
  ac_git_script_file   = env_has_key("AC_SCRIPT_FILENAME")
  ac_git_input_path    = get_env_variable("AC_SCRIPT_REPO_DIR")
  ac_git_clone_url     = get_env_variable("AC_SCRIPT_REPO_CLONE_URL")
  ac_git_username      = get_env_variable("AC_SCRIPT_GIT_USERNAME")
  ac_git_pat           = get_env_variable("AC_SCRIPT_GIT_PAT")
  ac_git_branch        = get_env_variable("AC_SCRIPT_GIT_BRANCH")
  ac_git_extra_params  = get_env_variable("AC_SCRIPT_EXTRA_PARAMETERS")

  if param_checker(ac_git_clone_url)
    if param_checker(ac_git_username, ac_git_pat)
      extra_header = set_the_authentication(ac_git_username, ac_git_pat)
      root_folder  = get_path_clone_repo(ac_git_clone_url, extra_header)
    else
      root_folder  = get_path_clone_repo(ac_git_clone_url)
    end
  elsif param_checker(ac_git_input_path)
    validate_input_script_folder(ac_git_input_path, ac_git_script_file)
    root_folder = ac_git_input_path
  else
    abort_with_message("Error: please provide either - AC_SCRIPT_REPO_DIR - or - AC_SCRIPT_REPO_CLONE_URL + AC_SCRIPT_GIT_USERNAME + AC_SCRIPT_GIT_PAT -")
  end

  script_args = prepare_args(ac_git_extra_params)
  execute_script_in(root_folder, ac_git_script_file, ac_git_branch, script_args)

  write_env_file(root_folder)

  puts 'Done.'.green
end

main
