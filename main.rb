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

def get_env_variable(key)
  value = ENV[key]
  value.nil? || value.strip.empty? ? abort_with_message("Missing #{key}") : value
end

def get_optional_env(key)
  value = ENV[key]
  value && !value.strip.empty? ? value : nil
end

def validate_input_script_folder(input_path, script_file)
  file_path = File.join(input_path, script_file)
  abort_with_message("Script file not found at CS_GIT_INPUT_PATH: #{file_path}") unless File.exist?(file_path)
end

def run_command(cmd)
  puts "@@[command] #{cmd}"
  output = `#{cmd}`
  puts output
  $CHILD_STATUS.success?
end

def get_path_cloned_repo(clone_url, branch, extra_header)
  abort_with_message('Missing CS_GIT_CLONE_URL or CS_GIT_BRANCH') if clone_url.nil? || clone_url.strip.empty? || branch.nil? || branch.strip.empty?
  root_folder = "Cloned_Script_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
  FileUtils.mkdir_p(root_folder)
  repo_name = File.basename(clone_url, '.git')
  repo_folder_path = File.join(root_folder, repo_name)
  FileUtils.cd(root_folder) do
    abort_with_message("Git clone failed: #{clone_url}") unless run_command("git -c \"#{extra_header}\" clone #{clone_url}")
    FileUtils.cd(repo_name) do
      abort_with_message("Git checkout failed: #{branch}") unless run_command("git checkout #{branch}")
    end
  end
  repo_folder_path
end

def prepare_args(raw_params)
  parts = Shellwords.split(raw_params.to_s.gsub(',', ' '))
  parts.empty? ? '' : " #{parts.join(' ')}"
end

def execute_script_in(folder, script_file, script_args)
  FileUtils.cd(folder) do
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
    File.open(env_path, 'a') do |f|
      f.puts "#{output_path}=#{root_folder}"
    end
  end
end

def set_the_extra_header(username, pat)
  abort_with_message('Missing CS_GIT_USERNAME or CS_GIT_PAT') if username.nil? || username.strip.empty? || pat.nil? || pat.strip.empty?
  auth = "#{username}:#{pat}"
  encoded = Base64.strict_encode64(auth)
  "http.extraheader=Authorization: Basic #{encoded}"
end

def main
  cs_git_script_file   = get_env_variable('AC_REUSABLE_REPO_SCRIPT_FILE')
  cs_git_input_path    = get_optional_env('AC_REUSABLE_REPO_PATH')
  cs_git_clone_url     = get_optional_env('AC_REUSABLE_REPO_SCRIPT_GIT_CLONE_URL')
  cs_git_username      = get_optional_env('AC_REUSABLE_REPO_SCRIPT_GIT_USERNAME')
  cs_git_pat           = get_optional_env('AC_REUSABLE_REPO_SCRIPT_GIT_PAT')
  cs_git_branch        = get_optional_env('AC_REUSABLE_REPO_SCRIPT_GIT_BRANCH')
  cs_git_extra_params  = get_optional_env('AC_REUSABLE_REPO_SCRIPT_EXTRA_PARAMETERS')
  cs_git_output_path   = get_optional_env('AC_REUSABLE_SCRIPT_OUTPUT_PATH')

  if cs_git_input_path && !cs_git_input_path.strip.empty?
    validate_input_script_folder(cs_git_input_path, cs_git_script_file)
    root_folder = cs_git_input_path
  else
    extra_header = set_the_extra_header(cs_git_username, cs_git_pat)
    root_folder = get_path_cloned_repo(cs_git_clone_url, cs_git_branch, extra_header)
  end

  script_args = prepare_args(cs_git_extra_params)
  execute_script_in(root_folder, cs_git_script_file, script_args)

  write_env_file(cs_git_output_path,root_folder)

  puts 'Done.'.green
end

main
