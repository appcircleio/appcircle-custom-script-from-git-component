require 'base64'
require 'fileutils'
require 'time'
require 'colored'
require 'English'

def abort_with_message(msg)
  abort msg.red
end

def run_command(cmd)
  puts "@@[command] #{cmd}".blue
  system(cmd) || abort_with_message("Command failed: #{cmd}")
end

cs_git_clone_url    = ENV['CS_GIT_CLONE_URL']   || abort_with_message('Missing CS_GIT_CLONE_URL')
cs_git_username     = ENV['CS_GIT_USERNAME']    || abort_with_message('Missing CS_GIT_USERNAME')
cs_git_pat          = ENV['CS_GIT_PAT']         || abort_with_message('Missing CS_GIT_PAT')
cs_git_branch       = ENV['CS_GIT_BRANCH']      || abort_with_message('Missing CS_GIT_BRANCH')
cs_git_script_file  = ENV['CS_GIT_SCRIPT_FILE'] || abort_with_message('Missing CS_GIT_SCRIPT_FILE')
cs_git_extra_params = ENV['CS_GIT_EXTRA_PARAMS'] || ''

# Prepare Git authentication header
auth          = "#{cs_git_username}:#{cs_git_pat}"
encoded_auth  = Base64.strict_encode64(auth)
header_option = "http.extraheader=Authorization: Basic #{encoded_auth}"

# Clone into timestamped folder
timestamp   = Time.now.strftime('%Y%m%d_%H%M%S')
root_folder = "Cloned_Script_#{timestamp}"
FileUtils.mkdir_p(root_folder)

FileUtils.cd(root_folder) do
  # Clone repository with optional extra Git params
  git_extra = cs_git_extra_params.strip.empty? ? '' : "#{cs_git_extra_params.strip} "
  clone_cmd = "git #{git_extra}-c \"#{header_option}\" clone #{cs_git_clone_url}"
  run_command(clone_cmd)

  # Checkout branch
  repo_name = File.basename(cs_git_clone_url, '.git')
  Dir.chdir(repo_name) do
    run_command("git checkout #{cs_git_branch}")

    # Verify script existence
    script = cs_git_script_file
    abort_with_message("Script file not found: #{script}") unless File.exist?(script)

    # Build execution command with extra script args
    script_args = cs_git_extra_params.strip.empty? ? '' : " #{cs_git_extra_params.strip}"

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
end

puts 'Done.'.green
