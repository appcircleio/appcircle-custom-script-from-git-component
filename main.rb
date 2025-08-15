#!/usr/bin/env ruby
require 'base64'
require 'fileutils'
require 'time'
require 'open3'
require 'colored'
require 'shellwords'

def abort_with_message(msg)
  msg.to_s.strip.split("\n").each do |line|
    puts "@@[error] #{line}"
  end
  abort
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

def get_current_branch
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  puts "Current branch: #{branch}".yellow
  branch
end

def validate_repo_path(repo_path)
  unless Dir.exist?(repo_path)
    abort_with_message(
      "Repository could not be found at: #{repo_path}\n" \
        "Please ensure that AC_SCRIPT_REPO_DIR points to a valid cloned repository that has been downloaded in a previous step."
    )
  end
end

def validate_script_path(input_path, branch, script_file)
  FileUtils.cd(input_path)

  unless branch.nil? || branch.strip.empty?
    run_command("git checkout #{branch}")
  end
  get_current_branch

  file_path = File.join(input_path, script_file)
  unless File.exist?(file_path)
    abort_with_message(
      "Script file not found at: #{file_path}\n" \
        "Please ensure that:\n" \
        "1. The file '#{script_file}' exists in the specified directory.\n" \
        "2. You have pulled the latest changes from the correct branch.\n"
    )
  end
end

def parse_command(cmd)
  cmd.is_a?(Array) ? cmd : Shellwords.split(cmd)
end

def format_printable(args)
  args.map { |t| t.match?(/\s/) ? %Q["#{t.gsub('"','\"')}"] : t }.join(' ')
end

def mask_sensitive_text(text)
  text.gsub(/(Authorization:\s*\w+\s+)\S+/, '\1********')
end

def print_command(text)
  puts "@@[command] #{text}"
end

def run_command(args)
  stdout, stderr, status = Open3.capture3(*args)
  puts stdout unless stdout.empty?
  raise "Command failed (#{status.exitstatus}):\n#{stderr}" unless status.success?
  true
end

def get_path_clone_repo(clone_url, branch, extra_header = nil)
  dir = env_has_key("AC_TEMP_DIR")
  FileUtils.cd(dir)
  root = "Cloned_Script_#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}_#{Process.pid}"
  FileUtils.mkdir_p(root)
  FileUtils.cd(root) do
    cmd = extra_header ? %Q[git -c "#{extra_header}" clone #{clone_url}] : "git clone #{clone_url}"
    args = parse_command(cmd)
    printable = format_printable(args)
    printable = mask_sensitive_text(printable) if extra_header
    print_command(printable)
    run_command(args)
  end
  repo = File.basename(clone_url, '.git')
  File.join(dir, root, repo)
end

def prepare_args(raw_params)
  params = raw_params.to_s.strip
  params = params.gsub(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/, ' ')
  Shellwords.split(params)
end

def execute_script_file(folder, script_file, script_args)
  FileUtils.cd(folder) do
    extname = File.extname(script_file).downcase
    case extname
    when '.sh'
      FileUtils.chmod('+x', script_file)
      run_command(["./#{script_file}", *script_args])
    when '.py'
      run_command(["python", script_file, *script_args])
    when '.rb'
      run_command(["ruby", script_file, *script_args])
    when '.pl'
      run_command(["perl", script_file, *script_args])
    when '.js'
      run_command(["node", script_file, *script_args])
    when '.java'
      run_command("javac -d . #{script_file}")
      class_name = File.basename(script_file, '.java')
      run_command(["java", "-cp", ".:#{File.dirname(script_file)}", class_name, *script_args])
    else
      abort_with_message("Unsupported script type: #{script_file}")
    end
  end
end

def write_env_file(ac_git_clone_url,env_var_name, value)
  return unless param_checker(ac_git_clone_url)
  File.open(env_has_key("AC_ENV_FILE_PATH"), 'a') do |f|
    f.puts "#{env_var_name}=#{value}"
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
  ac_git_repo_path     = get_env_variable("AC_SCRIPT_REPO_DIR")
  ac_git_clone_url     = get_env_variable("AC_SCRIPT_REPO_CLONE_URL")
  ac_git_username      = get_env_variable("AC_SCRIPT_GIT_USERNAME")
  ac_git_pat           = get_env_variable("AC_SCRIPT_GIT_PAT")
  ac_git_branch        = get_env_variable("AC_SCRIPT_GIT_BRANCH")
  ac_git_extra_params  = get_env_variable("AC_SCRIPT_EXTRA_PARAMETERS")

  if param_checker(ac_git_clone_url)
    if param_checker(ac_git_username,ac_git_pat)
      extra_header = set_the_authentication(ac_git_username, ac_git_pat)
    end
    repo_path = get_path_clone_repo(ac_git_clone_url, ac_git_branch, extra_header)
  elsif param_checker(ac_git_repo_path)
    validate_repo_path(ac_git_repo_path)
    repo_path = ac_git_repo_path
  else
    abort_with_message("Error: Please provide either `AC_SCRIPT_REPO_DIR` or `AC_SCRIPT_REPO_CLONE_URL`.")
  end

  validate_script_path(repo_path, ac_git_branch, ac_git_script_file)
  script_args = prepare_args(ac_git_extra_params)
  execute_script_file(repo_path, ac_git_script_file, script_args)

  write_env_file(ac_git_clone_url, "AC_SCRIPT_REPO_OUTPUT_DIR", repo_path)

  puts 'Custom script execution completed successfully.'.green

end

main
