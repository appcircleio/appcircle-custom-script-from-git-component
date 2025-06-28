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

def get_optional_env(key)
  value = ENV[key]
  value && !value.strip.empty? ? value : nil
end

def validate_script_folder_input(input_path, script_file)
  file_path = File.join(input_path, script_file)
  abort_with_message("Script file not found at CS_GIT_INPUT_PATH: #{file_path}") unless File.exist?(file_path)
end

def run_command(cmd)
  puts "@@[command] #{cmd}"
  output = `#{cmd}`
  puts output
  $CHILD_STATUS.success?
end

def determine_script_folder(clone_url, branch, extra_header)
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

def write_env_file(env_path, root_folder)
  return unless env_path && !env_path.strip.empty?
  existing = File.exist?(env_path) ? File.read(env_path) : ''
  unless existing.include?('RUN_SCRIPT_WORKDIR=')
    File.open(env_path, 'a') { |f| f.puts "RUN_SCRIPT_WORKDIR=#{root_folder}" }
  end
end

def handle_output_path(output_path, root_folder)
  return unless output_path && !output_path.strip.empty?
  FileUtils.mkdir_p(output_path)
  FileUtils.cp_r(Dir.glob(File.join(root_folder, '*')), output_path)
  puts "@@[info] Copied results from #{root_folder} to #{output_path}".green
end

def build_extra_header(username, pat)
  abort_with_message('Missing CS_GIT_USERNAME or CS_GIT_PAT') if username.nil? || username.strip.empty? || pat.nil? || pat.strip.empty?
  auth = "#{username}:#{pat}"
  encoded = Base64.strict_encode64(auth)
  "http.extraheader=Authorization: Basic #{encoded}"
end

def main
  cs_git_script_file   = get_env_variable('CS_GIT_SCRIPT_FILE')
  cs_git_input_path    = get_optional_env('CS_GIT_INPUT_PATH')
  cs_git_clone_url     = get_optional_env('CS_GIT_CLONE_URL')
  cs_git_username      = get_optional_env('CS_GIT_USERNAME')
  cs_git_pat           = get_optional_env('CS_GIT_PAT')
  cs_git_branch        = get_optional_env('CS_GIT_BRANCH')
  cs_git_extra_params  = get_optional_env('CS_GIT_EXTRA_PARAMS')
  cs_git_output_path   = get_optional_env('CS_GIT_OUTPUT_PATH')
  ac_env_file_path     = get_optional_env('AC_ENV_FILE_PATH')

  if cs_git_input_path && !cs_git_input_path.strip.empty?
    validate_script_folder_input(cs_git_input_path, cs_git_script_file)
    root_folder = cs_git_input_path
  else
    extra_header = build_extra_header(cs_git_username, cs_git_pat)
    root_folder = determine_script_folder(cs_git_clone_url, cs_git_branch, extra_header)
  end

  script_args = prepare_args(cs_git_extra_params)
  execute_script_in(root_folder, cs_git_script_file, script_args)

  write_env_file(ac_env_file_path, root_folder)
  handle_output_path(cs_git_output_path, root_folder)
  puts 'Done.'.green
end

main
