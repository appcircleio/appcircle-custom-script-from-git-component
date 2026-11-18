# frozen_string_literal: true

# ─── Coverage (must start before loading main.rb) ─────────────────────────────
require 'coverage'
Coverage.start unless Coverage.running?

# ─── Dependencies ─────────────────────────────────────────────────────────────
require 'rspec'
require 'rspec/core/formatters/base_formatter'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'stringio'
require 'json'
require 'rbconfig'
require 'base64'

MAIN_RB      = File.expand_path('../main.rb', __dir__)
PROJECT_ROOT = File.dirname(MAIN_RB)

# main.rb tolerates a missing 'colored' gem at require time, but still calls
# String#yellow / #green. A stub 'colored.rb' is written to a temporary directory
# and put on the load path only when the real gem cannot be found. Subprocess runs
# get the same directory on RUBYLIB.
STUB_LIB_DIR = Dir.mktmpdir('colored_stub')
File.write(File.join(STUB_LIB_DIR, 'colored.rb'), <<~RUBY)
  class String
    %i[blue red green yellow cyan].each do |color|
      define_method(color) { self } unless method_defined?(color)
    end
  end
RUBY

begin
  require 'colored'
rescue LoadError
  $LOAD_PATH.unshift(STUB_LIB_DIR)
end

require MAIN_RB

# Subprocess runs of main.rb load this hook (via `-r coverage_hook`) and dump
# their line coverage of main.rb so it can be merged into the final report.
SUBPROCESS_COVERAGE_DIR = File.join(STUB_LIB_DIR, 'coverage')
FileUtils.mkdir_p(SUBPROCESS_COVERAGE_DIR)
File.write(File.join(STUB_LIB_DIR, 'coverage_hook.rb'), <<~RUBY)
  require 'coverage'
  require 'json'
  Coverage.start
  at_exit do
    target = ENV['AC_TEST_COVERAGE_TARGET']
    result = Coverage.result
    lines  = result[target] || result[File.realpath(target)] rescue nil
    if lines
      File.write(File.join(ENV['AC_TEST_COVERAGE_DIR'], "\#{Process.pid}-\#{rand(1_000_000)}.json"), JSON.dump(lines))
    end
  end
RUBY

# ─── Custom Formatter ─────────────────────────────────────────────────────────
class ReadableFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register(
    self,
    :example_group_started,
    :example_group_finished,
    :example_passed,
    :example_failed,
    :example_pending,
    :dump_summary
  )

  PASS  = "\e[32;1m[ PASS ]\e[0m"
  FAIL  = "\e[31;1m[ FAIL ]\e[0m"
  ERROR = "\e[31;1m[ERROR ]\e[0m"
  SKIP  = "\e[33;1m[ SKIP ]\e[0m"

  DIVIDER     = "\e[90m#{'─' * 72}\e[0m"
  DIVIDER_FAT = "\e[90m#{'═' * 72}\e[0m"

  def initialize(output)
    super
    @depth    = 0
    @failures = []
    @counts   = { passed: 0, failed: 0, pending: 0 }
  end

  # Top-level describe groups cycle through distinct colors
  GROUP_COLORS = [
    "\e[34;1m",  # bold blue
    "\e[35;1m",  # bold magenta
    "\e[36;1m",  # bold cyan
    "\e[33;1m",  # bold yellow
  ].freeze

  def example_group_started(notification)
    group = notification.group
    if group.parent_groups.size <= 1
      output.puts if @depth.zero?
      color = GROUP_COLORS[@depth % GROUP_COLORS.size]
      output.puts "  #{color}#{group.description}\e[0m"
    else
      output.puts "    #{'  ' * (@depth - 1)}\e[90m▸ \e[0m\e[37m#{group.description}\e[0m"
    end
    @depth += 1
  end

  def example_group_finished(_notification)
    @depth -= 1 if @depth > 0
  end

  def example_passed(notification)
    @counts[:passed] += 1
    print_example(PASS, notification.example)
  end

  def example_failed(notification)
    @counts[:failed] += 1
    ex    = notification.example
    exc   = ex.execution_result.exception
    badge = exc.is_a?(RSpec::Expectations::ExpectationNotMetError) ? FAIL : ERROR
    print_example(badge, ex)
    @failures << notification
  end

  def example_pending(notification)
    @counts[:pending] += 1
    ex = notification.example
    output.puts "    #{'  ' * [0, @depth - 1].max}#{SKIP}  #{ex.description}"
  end

  def dump_summary(notification)
    output.puts
    output.puts DIVIDER_FAT

    unless @failures.empty?
      output.puts "\n  \e[1;31mFailures:\e[0m\n"
      @failures.each_with_index do |n, i|
        ex  = n.example
        exc = ex.execution_result.exception
        output.puts "  \e[1m#{i + 1}) #{ex.full_description}\e[0m"
        exc.message.lines.first(6).each do |line|
          output.puts "     \e[31m#{line.rstrip}\e[0m"
        end
        output.puts "     \e[90m# #{ex.location}\e[0m"
        output.puts
      end
      output.puts DIVIDER
    end

    t   = notification.examples.size
    p   = @counts[:passed]
    f   = @counts[:failed]
    s   = @counts[:pending]
    sec = format('%.3fs', notification.duration)

    parts = ["\e[32m#{p} passed\e[0m"]
    parts << "\e[31m#{f} failed\e[0m"  if f > 0
    parts << "\e[33m#{s} pending\e[0m" if s > 0

    overall = f.zero? ? "\e[32;1m✔  All #{t} tests passed\e[0m" : "\e[31;1m✖  #{f} of #{t} tests failed\e[0m"
    output.puts "\n  #{overall}"
    output.puts "  #{parts.join('  |  ')}  \e[90m(#{sec})\e[0m"
    output.puts DIVIDER_FAT
  end

  private

  def print_example(badge, example)
    indent = '  ' * [0, @depth - 1].max
    time   = format('%.3fs', example.execution_result.run_time)
    output.puts "    #{indent}#{badge}  #{example.description}  \e[90m(#{time})\e[0m"
  end
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Every ENV key main.rb reads. In-process tests reset them around each example
# and subprocess tests unset them, so the ambient shell can never leak in.
MAIN_ENV_KEYS = %w[
  AC_SCRIPT_FILENAME
  AC_SCRIPT_REPO_DIR
  AC_SCRIPT_REPO_CLONE_URL
  AC_SCRIPT_GIT_USERNAME
  AC_SCRIPT_GIT_PAT
  AC_SCRIPT_GIT_BRANCH
  AC_SCRIPT_EXTRA_PARAMETERS
  AC_TEMP_DIR
  AC_ENV_FILE_PATH
].freeze

def with_env(vars)
  previous = vars.keys.to_h { |k| [k, [ENV.key?(k), ENV[k]]] }
  vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  yield
ensure
  previous.each { |k, (had_key, old)| had_key ? ENV[k] = old : ENV.delete(k) }
end

# Asserts that the block aborts (SystemExit, status 1) and prints `message`
# through abort_with_message's "@@[error]" prefix.
def expect_abort(message, &block)
  expect { expect(&block).to raise_error(SystemExit) { |e| expect(e.status).to eq(1) } }
    .to output(/@@\[error\] #{Regexp.escape(message)}/).to_stdout
end

def fake_status(success, exitstatus = success ? 0 : 1)
  instance_double(Process::Status, success?: success, exitstatus: exitstatus)
end

def write_executable(path, content)
  File.write(path, content)
  File.chmod(0o755, path)
end

# Fake `git` for subprocess tests. It logs every invocation and never touches the
# network: `clone <url>` creates <repo>/run.sh, `rev-parse` prints a branch name.
def build_fake_git(base)
  bin = File.join(base, 'bin')
  log = File.join(base, 'git.log')
  FileUtils.mkdir_p(bin)
  write_executable(File.join(bin, 'git'), <<~SH)
    #!/bin/sh
    echo "git $*" >> "#{log}"
    for arg; do last="$arg"; done
    case "$*" in
      *clone*)
        repo=$(basename "$last" .git)
        mkdir -p "$repo"
        printf '#!/bin/sh\\necho "fixture ran $*"\\n' > "$repo/run.sh"
        ;;
      "rev-parse --abbrev-ref HEAD")
        echo fake-branch
        ;;
    esac
  SH
  { bin: bin, log: log }
end

# Run main.rb in a subprocess with a clean environment plus the stub 'colored'.
def run_main(env = {}, fake_bin: nil)
  clean_env = MAIN_ENV_KEYS.to_h { |k| [k, nil] }.merge(
    'RUBYLIB'                 => STUB_LIB_DIR,
    'AC_TEST_COVERAGE_TARGET' => MAIN_RB,
    'AC_TEST_COVERAGE_DIR'    => SUBPROCESS_COVERAGE_DIR
  )
  clean_env['PATH'] = "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV['PATH']}" if fake_bin
  Open3.capture3(clean_env.merge(env), RbConfig.ruby, '-r', 'coverage_hook', MAIN_RB)
end

RSpec.configure do |config|
  # Functions under test FileUtils.cd into tmp dirs, print progress and read ENV.
  # Restore the working directory and ENV, and keep their output out of the report.
  config.around do |example|
    pwd = Dir.pwd
    saved_env = MAIN_ENV_KEYS.to_h { |k| [k, ENV[k]] }
    MAIN_ENV_KEYS.each { |k| ENV.delete(k) }
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      example.run
    ensure
      $stdout = original_stdout
      saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      Dir.chdir(pwd)
    end
  end
end

# ─── Tests ────────────────────────────────────────────────────────────────────

RSpec.describe 'main.rb loading' do
  it 'can be required without running the script body' do
    out, err, status = Open3.capture3({ 'RUBYLIB' => STUB_LIB_DIR }, RbConfig.ruby, '-e', "require #{MAIN_RB.dump}; puts 'loaded'")
    expect(status.exitstatus).to eq(0), "stderr: #{err}"
    expect(out).to eq("loaded\n")
  end

  it "can be required when the 'colored' gem is not installed" do
    hide_colored = <<~RUBY
      module Kernel
        alias_method :__orig_require, :require
        def require(name)
          raise LoadError, "cannot load such file -- \#{name}" if name == 'colored'
          __orig_require(name)
        end
      end
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, '-e', "#{hide_colored}\nrequire #{MAIN_RB.dump}; puts 'loaded'")
    expect(status.exitstatus).to eq(0), "stderr: #{err}"
    expect(out).to eq("loaded\n")
  end
end

RSpec.describe '#abort_with_message' do
  it 'prints each line with the @@[error] prefix and exits 1' do
    expect do
      expect { abort_with_message("first\nsecond") }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end.to output("@@[error] first\n@@[error] second\n").to_stdout
  end

  it 'strips surrounding whitespace before printing' do
    expect_abort('trimmed') { abort_with_message("  trimmed  \n") }
  end

  it 'prints nothing but still exits for an empty message' do
    expect { expect { abort_with_message('') }.to raise_error(SystemExit) }.not_to output.to_stdout
  end

  it 'prints nothing but still exits for a nil message' do
    expect { expect { abort_with_message(nil) }.to raise_error(SystemExit) }.not_to output.to_stdout
  end
end

RSpec.describe '#env_has_key' do
  it 'returns the value when the key is set' do
    with_env('AC_TEMP_DIR' => '/tmp/x') { expect(env_has_key('AC_TEMP_DIR')).to eq('/tmp/x') }
  end

  it 'aborts with "Missing <key>" when the key is not set' do
    expect_abort('Missing AC_TEMP_DIR') { env_has_key('AC_TEMP_DIR') }
  end

  it 'aborts when the value is empty' do
    with_env('AC_TEMP_DIR' => '') { expect_abort('Missing AC_TEMP_DIR') { env_has_key('AC_TEMP_DIR') } }
  end

  it 'aborts when the value is whitespace only' do
    with_env('AC_TEMP_DIR' => "  \t") { expect_abort('Missing AC_TEMP_DIR') { env_has_key('AC_TEMP_DIR') } }
  end
end

RSpec.describe '#get_env_variable' do
  it 'returns the value when the key is set' do
    with_env('AC_SCRIPT_GIT_BRANCH' => 'develop') { expect(get_env_variable('AC_SCRIPT_GIT_BRANCH')).to eq('develop') }
  end

  it 'returns nil when the key is not set' do
    expect(get_env_variable('AC_SCRIPT_GIT_BRANCH')).to be_nil
  end

  it 'returns nil for an empty or whitespace-only value' do
    with_env('AC_SCRIPT_GIT_BRANCH' => '') { expect(get_env_variable('AC_SCRIPT_GIT_BRANCH')).to be_nil }
    with_env('AC_SCRIPT_GIT_BRANCH' => '   ') { expect(get_env_variable('AC_SCRIPT_GIT_BRANCH')).to be_nil }
  end
end

RSpec.describe '#param_checker' do
  it 'returns true when every param is non-blank' do
    expect(param_checker('user', 'token')).to be(true)
  end

  it 'returns false when any param is nil' do
    expect(param_checker('user', nil)).to be(false)
  end

  it 'returns false when any param is empty or whitespace' do
    expect(param_checker('', 'token')).to be(false)
    expect(param_checker('user', '  ')).to be(false)
  end

  it 'returns true when called with no params (current behaviour)' do
    expect(param_checker).to be(true)
  end
end

RSpec.describe '#get_current_branch' do
  it 'returns the stripped output of `git rev-parse --abbrev-ref HEAD`' do
    expect(self).to receive(:`).with('git rev-parse --abbrev-ref HEAD').and_return("feature/x\n")
    expect(get_current_branch).to eq('feature/x')
  end

  it 'prints the current branch' do
    allow(self).to receive(:`).and_return("main\n")
    expect { get_current_branch }.to output(/Current branch: main/).to_stdout
  end

  it 'returns an empty string when git prints nothing (e.g. not a repository)' do
    allow(self).to receive(:`).and_return('')
    expect(get_current_branch).to eq('')
  end
end

RSpec.describe '#validate_repo_path' do
  it 'returns without aborting when the directory exists' do
    Dir.mktmpdir { |dir| expect { validate_repo_path(dir) }.not_to raise_error }
  end

  it 'aborts with guidance when the directory does not exist' do
    Dir.mktmpdir do |dir|
      missing = File.join(dir, 'missing')
      expect_abort("Repository could not be found at: #{missing}") { validate_repo_path(missing) }
    end
  end

  it 'aborts for an empty path' do
    expect_abort('Repository could not be found at:') { validate_repo_path('') }
  end

  it 'raises ArgumentError with context for a nil path' do
    expect { validate_repo_path(nil) }.to raise_error(ArgumentError, 'validate_repo_path: repo_path is nil')
  end
end

RSpec.describe '#validate_script_path' do
  around do |example|
    Dir.mktmpdir do |dir|
      @repo = dir
      File.write(File.join(@repo, 'build.sh'), "echo hi\n")
      example.run
    end
  end

  before { allow(self).to receive(:`).and_return("main\n") }

  it 'changes into the repository and accepts an existing script without checkout' do
    expect(self).not_to receive(:run_command)
    expect { validate_script_path(@repo, nil, 'build.sh') }.not_to raise_error
    expect(File.realpath(Dir.pwd)).to eq(File.realpath(@repo))
  end

  it 'skips checkout for an empty or whitespace branch' do
    expect(self).not_to receive(:run_command)
    validate_script_path(@repo, '  ', 'build.sh')
  end

  it 'checks out the requested branch first' do
    expect(self).to receive(:run_command).with('git checkout develop').ordered
    expect(self).to receive(:get_current_branch).ordered
    validate_script_path(@repo, 'develop', 'build.sh')
  end

  it 'supports a script in a sub folder' do
    FileUtils.mkdir_p(File.join(@repo, 'scripts'))
    File.write(File.join(@repo, 'scripts', 'deploy.py'), '')
    expect { validate_script_path(@repo, nil, 'scripts/deploy.py') }.not_to raise_error
  end

  it 'aborts when the script file does not exist' do
    expect_abort("Script file not found at: #{File.join(@repo, 'missing.sh')}") do
      validate_script_path(@repo, nil, 'missing.sh')
    end
  end

  it 'propagates the error when the checkout fails' do
    allow(self).to receive(:run_command).and_raise(RuntimeError, 'Command failed (1)')
    expect { validate_script_path(@repo, 'nope', 'build.sh') }.to raise_error(RuntimeError, /Command failed/)
  end

  it 'raises when the repository directory does not exist' do
    expect { validate_script_path(File.join(@repo, 'missing'), nil, 'build.sh') }.to raise_error(Errno::ENOENT)
  end

  it 'raises ArgumentError with context for a nil script file, before any checkout' do
    expect(self).not_to receive(:run_command)
    expect { validate_script_path(@repo, 'develop', nil) }
      .to raise_error(ArgumentError, 'validate_script_path: script_file is nil')
  end

  it 'raises ArgumentError with context for a nil input path' do
    expect { validate_script_path(nil, nil, 'build.sh') }
      .to raise_error(ArgumentError, 'validate_script_path: input_path is nil')
  end
end

RSpec.describe '#parse_command' do
  it 'splits a command string shell-style' do
    expect(parse_command(%q[git -c "http.extraheader=Authorization: Basic abc" clone https://h/r.git]))
      .to eq(['git', '-c', 'http.extraheader=Authorization: Basic abc', 'clone', 'https://h/r.git'])
  end

  it 'returns an array unchanged' do
    args = ['git', 'clone', 'url']
    expect(parse_command(args)).to equal(args)
  end

  it 'returns an empty array for an empty string' do
    expect(parse_command('')).to eq([])
  end

  it 'raises for unbalanced quotes' do
    expect { parse_command('git "clone') }.to raise_error(ArgumentError)
  end

  it 'raises ArgumentError with context for nil' do
    expect { parse_command(nil) }.to raise_error(ArgumentError, 'parse_command: cmd is nil')
  end
end

RSpec.describe '#format_printable' do
  it 'joins plain args with spaces' do
    expect(format_printable(%w[git clone https://h/r.git])).to eq('git clone https://h/r.git')
  end

  it 'quotes args that contain whitespace and escapes their double quotes' do
    expect(format_printable(['echo', 'a b', 'say "hi" now'])).to eq('echo "a b" "say \"hi\" now"')
  end

  it 'returns an empty string for an empty array' do
    expect(format_printable([])).to eq('')
  end

  it 'raises ArgumentError with context for nil' do
    expect { format_printable(nil) }.to raise_error(ArgumentError, 'format_printable: args is nil')
  end
end

RSpec.describe '#mask_sensitive_text' do
  it 'masks the credential of an Authorization header' do
    expect(mask_sensitive_text('Authorization: Basic dXNlcjpwYXQ= rest')).to eq('Authorization: Basic ******** rest')
  end

  it 'also swallows a closing quote glued to the credential (current behaviour)' do
    text = 'git -c "http.extraheader=Authorization: Basic dXNlcjpwYXQ=" clone https://h/r.git'
    expect(mask_sensitive_text(text))
      .to eq('git -c "http.extraheader=Authorization: Basic ******** clone https://h/r.git')
  end

  it 'leaves text without an Authorization header untouched' do
    expect(mask_sensitive_text('git clone https://h/r.git')).to eq('git clone https://h/r.git')
  end

  it 'returns an empty string for empty input' do
    expect(mask_sensitive_text('')).to eq('')
  end

  it 'raises ArgumentError with context for nil' do
    expect { mask_sensitive_text(nil) }.to raise_error(ArgumentError, 'mask_sensitive_text: text is nil')
  end
end

RSpec.describe '#print_command' do
  it 'prints the text with the @@[command] prefix' do
    expect { print_command('git clone url') }.to output("@@[command] git clone url\n").to_stdout
  end

  it 'prints only the prefix for empty or nil text' do
    expect { print_command('') }.to output("@@[command] \n").to_stdout
    expect { print_command(nil) }.to output("@@[command] \n").to_stdout
  end
end

RSpec.describe '#run_command' do
  it 'passes the args to Open3.capture3, prints stdout and returns true' do
    expect(Open3).to receive(:capture3).with('git', 'clone', 'url').and_return(["cloned\n", '', fake_status(true)])
    result = nil
    expect { result = run_command(%w[git clone url]) }.to output("cloned\n").to_stdout
    expect(result).to be(true)
  end

  it 'passes a plain string as a single command' do
    expect(Open3).to receive(:capture3).with('javac -d . A.java').and_return(['', '', fake_status(true)])
    run_command('javac -d . A.java')
  end

  it 'prints nothing when stdout is empty' do
    allow(Open3).to receive(:capture3).and_return(['', '', fake_status(true)])
    expect { run_command(['true']) }.not_to output.to_stdout
  end

  it 'raises with the exit status and stderr when the command fails' do
    allow(Open3).to receive(:capture3).and_return(['', "fatal: boom\n", fake_status(false, 128)])
    expect { run_command(%w[git clone url]) }.to raise_error(RuntimeError, "Command failed (128):\nfatal: boom\n")
  end

  it 'raises when the args are empty (current behaviour)' do
    expect { run_command([]) }.to raise_error(ArgumentError)
  end
end

RSpec.describe '#get_path_clone_repo' do
  around do |example|
    Dir.mktmpdir do |dir|
      @temp = dir
      with_env('AC_TEMP_DIR' => dir) { example.run }
    end
  end

  it 'clones into a unique folder under AC_TEMP_DIR and returns the repo path' do
    expect(self).to receive(:run_command).with(%w[git clone https://h/org/scripts.git])
    path = get_path_clone_repo('https://h/org/scripts.git', nil)
    expect(path).to match(%r{\A#{Regexp.escape(@temp)}/Cloned_Script_\d{8}_\d{6}_\d{3}_#{Process.pid}/scripts\z})
    expect(File).to be_directory(File.dirname(path))
  end

  it 'prints the clone command' do
    allow(self).to receive(:run_command)
    expect { get_path_clone_repo('https://h/org/scripts.git', 'main') }
      .to output(%r{@@\[command\] git clone https://h/org/scripts\.git}).to_stdout
  end

  it 'passes the extra header to git and masks it in the printed command' do
    header = 'http.extraheader=Authorization: Basic c2VjcmV0'
    expect(self).to receive(:run_command).with(['git', '-c', header, 'clone', 'https://h/r.git'])
    out = StringIO.new
    $stdout = out
    get_path_clone_repo('https://h/r.git', nil, header)
    expect(out.string).to include('@@[command] git -c "http.extraheader=Authorization: Basic ******** clone https://h/r.git')
    expect(out.string).not_to include('c2VjcmV0')
  end

  it 'aborts when AC_TEMP_DIR is missing' do
    with_env('AC_TEMP_DIR' => nil) do
      expect(self).not_to receive(:run_command)
      expect_abort('Missing AC_TEMP_DIR') { get_path_clone_repo('https://h/r.git', nil) }
    end
  end

  it 'propagates the error when git clone fails' do
    allow(self).to receive(:run_command).and_raise(RuntimeError, 'Command failed (128)')
    expect { get_path_clone_repo('https://h/r.git', nil) }.to raise_error(RuntimeError, /Command failed/)
  end
end

RSpec.describe '#prepare_args' do
  it 'splits comma separated params' do
    expect(prepare_args('a,b,c')).to eq(%w[a b c])
  end

  it 'keeps quoted params with spaces and commas together' do
    expect(prepare_args('param1,param2,"param3 with spaces",param4')).to eq(['param1', 'param2', 'param3 with spaces', 'param4'])
    expect(prepare_args('"a,b",c')).to eq(['a,b', 'c'])
  end

  it 'returns an empty array for nil or blank input' do
    expect(prepare_args(nil)).to eq([])
    expect(prepare_args('   ')).to eq([])
  end

  it 'raises for an unbalanced quote' do
    expect { prepare_args('a,"b') }.to raise_error(ArgumentError)
  end
end

RSpec.describe '#execute_script_file' do
  around do |example|
    Dir.mktmpdir do |dir|
      @folder = dir
      example.run
    end
  end

  {
    'run.py' => %w[python run.py],
    'run.rb' => %w[ruby run.rb],
    'run.pl' => %w[perl run.pl],
    'run.js' => %w[node run.js],
    'RUN.PY' => %w[python RUN.PY]
  }.each do |file, command|
    it "runs #{file} as `#{command.join(' ')} <args>`" do
      expect(self).to receive(:run_command).with([*command, 'a', 'b c'])
      execute_script_file(@folder, file, ['a', 'b c'])
    end
  end

  it 'makes a .sh script executable and runs it directly' do
    script = File.join(@folder, 'run.sh')
    File.write(script, "#!/bin/sh\n")
    File.chmod(0o644, script)
    expect(self).to receive(:run_command).with(['./run.sh', 'x'])
    execute_script_file(@folder, 'run.sh', ['x'])
    expect(File.executable?(script)).to be(true)
  end

  it 'compiles and runs a .java file' do
    expect(self).to receive(:run_command).with('javac -d . Main.java').ordered
    expect(self).to receive(:run_command).with(['java', '-cp', '.:.', 'Main', 'x']).ordered
    execute_script_file(@folder, 'Main.java', ['x'])
  end

  it 'uses the script sub folder on the java classpath' do
    expect(self).to receive(:run_command).with('javac -d . src/App.java')
    expect(self).to receive(:run_command).with(['java', '-cp', '.:src', 'App'])
    execute_script_file(@folder, 'src/App.java', [])
  end

  it 'runs the command from inside the folder and restores the working directory' do
    pwd = Dir.pwd
    expect(self).to receive(:run_command) { expect(File.realpath(Dir.pwd)).to eq(File.realpath(@folder)) }
    execute_script_file(@folder, 'run.rb', [])
    expect(Dir.pwd).to eq(pwd)
  end

  it 'aborts for an unsupported script type' do
    expect(self).not_to receive(:run_command)
    expect_abort('Unsupported script type: run.txt') { execute_script_file(@folder, 'run.txt', []) }
  end

  it 'aborts for a file without an extension' do
    expect_abort('Unsupported script type: Makefile') { execute_script_file(@folder, 'Makefile', []) }
  end

  it 'raises for a .sh script that does not exist' do
    expect { execute_script_file(@folder, 'missing.sh', []) }.to raise_error(Errno::ENOENT)
  end

  it 'raises ArgumentError with context for a nil script file' do
    expect(self).not_to receive(:run_command)
    expect { execute_script_file(@folder, nil, []) }
      .to raise_error(ArgumentError, 'execute_script_file: script_file is nil')
  end

  it 'raises ArgumentError with context for a nil folder' do
    expect { execute_script_file(nil, 'run.sh', []) }
      .to raise_error(ArgumentError, 'execute_script_file: folder is nil')
  end
end

RSpec.describe '#write_env_file' do
  around do |example|
    Dir.mktmpdir do |dir|
      @env_file = File.join(dir, 'env')
      example.run
    end
  end

  it 'appends NAME=value to AC_ENV_FILE_PATH when a clone url is given' do
    File.write(@env_file, "EXISTING=1\n")
    with_env('AC_ENV_FILE_PATH' => @env_file) { write_env_file('https://h/r.git', 'AC_SCRIPT_REPO_OUTPUT_DIR', '/w/r') }
    expect(File.read(@env_file)).to eq("EXISTING=1\nAC_SCRIPT_REPO_OUTPUT_DIR=/w/r\n")
  end

  it 'does nothing when the clone url is nil or blank' do
    with_env('AC_ENV_FILE_PATH' => @env_file) do
      write_env_file(nil, 'AC_SCRIPT_REPO_OUTPUT_DIR', '/w/r')
      write_env_file(' ', 'AC_SCRIPT_REPO_OUTPUT_DIR', '/w/r')
    end
    expect(File).not_to exist(@env_file)
  end

  it 'aborts when AC_ENV_FILE_PATH is missing' do
    expect_abort('Missing AC_ENV_FILE_PATH') { write_env_file('https://h/r.git', 'X', 'y') }
  end
end

RSpec.describe '#set_the_authentication' do
  it 'builds a basic-auth git extra header' do
    expect(set_the_authentication('user', 'pat'))
      .to eq("http.extraheader=Authorization: Basic #{Base64.strict_encode64('user:pat')}")
  end

  it 'still builds a header for empty credentials, because ":" is never blank (current behaviour)' do
    expect(set_the_authentication('', '')).to eq('http.extraheader=Authorization: Basic Og==')
    expect(set_the_authentication(nil, nil)).to eq('http.extraheader=Authorization: Basic Og==')
  end
end

RSpec.describe '#main' do
  before do
    allow(self).to receive(:get_path_clone_repo).and_return('/cloned/repo')
    allow(self).to receive(:validate_repo_path)
    allow(self).to receive(:validate_script_path)
    allow(self).to receive(:execute_script_file)
    allow(self).to receive(:write_env_file)
  end

  it 'clones without auth, runs the script and writes the output dir' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/r.git',
             'AC_SCRIPT_GIT_BRANCH' => 'dev', 'AC_SCRIPT_EXTRA_PARAMETERS' => 'a,"b c"') do
      expect(self).to receive(:get_path_clone_repo).with('https://h/r.git', 'dev', nil)
      expect(self).to receive(:validate_script_path).with('/cloned/repo', 'dev', 'run.sh')
      expect(self).to receive(:execute_script_file).with('/cloned/repo', 'run.sh', ['a', 'b c'])
      expect(self).to receive(:write_env_file).with('https://h/r.git', 'AC_SCRIPT_REPO_OUTPUT_DIR', '/cloned/repo')
      expect { main }.to output(/Custom script execution completed successfully\./).to_stdout
    end
  end

  it 'clones with an auth header when username and PAT are set' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/r.git',
             'AC_SCRIPT_GIT_USERNAME' => 'u', 'AC_SCRIPT_GIT_PAT' => 'p') do
      expect(self).to receive(:get_path_clone_repo)
        .with('https://h/r.git', nil, "http.extraheader=Authorization: Basic #{Base64.strict_encode64('u:p')}")
      main
    end
  end

  it 'clones without auth when only one of username / PAT is set' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/r.git',
             'AC_SCRIPT_GIT_USERNAME' => 'u') do
      expect(self).to receive(:get_path_clone_repo).with('https://h/r.git', nil, nil)
      main
    end
  end

  it 'uses AC_SCRIPT_REPO_DIR when no clone url is given' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => '/existing/repo') do
      expect(self).not_to receive(:get_path_clone_repo)
      expect(self).to receive(:validate_repo_path).with('/existing/repo')
      expect(self).to receive(:execute_script_file).with('/existing/repo', 'run.sh', [])
      expect(self).to receive(:write_env_file).with(nil, 'AC_SCRIPT_REPO_OUTPUT_DIR', '/existing/repo')
      main
    end
  end

  it 'prefers the clone url when both the clone url and the repo dir are set' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => '/existing/repo',
             'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/r.git') do
      expect(self).not_to receive(:validate_repo_path)
      expect(self).to receive(:execute_script_file).with('/cloned/repo', 'run.sh', [])
      main
    end
  end

  it 'aborts when neither AC_SCRIPT_REPO_DIR nor AC_SCRIPT_REPO_CLONE_URL is set' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh') do
      expect(self).not_to receive(:execute_script_file)
      expect_abort('Error: Please provide either `AC_SCRIPT_REPO_DIR` or `AC_SCRIPT_REPO_CLONE_URL`.') { main }
    end
  end

  it 'aborts when AC_SCRIPT_FILENAME is missing' do
    with_env('AC_SCRIPT_REPO_DIR' => '/existing/repo') do
      expect(self).not_to receive(:execute_script_file)
      expect_abort('Missing AC_SCRIPT_FILENAME') { main }
    end
  end

  it 'propagates a script failure and does not write the env file' do
    with_env('AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => '/existing/repo') do
      allow(self).to receive(:execute_script_file).and_raise(RuntimeError, 'Command failed (2)')
      expect(self).not_to receive(:write_env_file)
      expect { main }.to raise_error(RuntimeError, /Command failed/)
    end
  end
end

RSpec.describe 'ENV validation (subprocess)' do
  around do |example|
    Dir.mktmpdir do |dir|
      @repo = dir
      example.run
    end
  end

  [['missing', nil], ['empty', ''], ['whitespace only', '   ']].each do |label, value|
    it "exits 1 with 'Missing AC_SCRIPT_FILENAME' when AC_SCRIPT_FILENAME is #{label}" do
      out, _err, status = run_main({ 'AC_SCRIPT_FILENAME' => value, 'AC_SCRIPT_REPO_DIR' => @repo })
      expect(status.exitstatus).to eq(1)
      expect(out).to include('@@[error] Missing AC_SCRIPT_FILENAME')
    end
  end

  [['missing', nil], ['empty', '']].each do |label, value|
    it "exits 1 when both AC_SCRIPT_REPO_DIR and AC_SCRIPT_REPO_CLONE_URL are #{label}" do
      out, _err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh',
                                     'AC_SCRIPT_REPO_DIR' => value, 'AC_SCRIPT_REPO_CLONE_URL' => value })
      expect(status.exitstatus).to eq(1)
      expect(out).to include('@@[error] Error: Please provide either `AC_SCRIPT_REPO_DIR` or `AC_SCRIPT_REPO_CLONE_URL`.')
    end
  end

  it 'exits 1 when AC_SCRIPT_REPO_DIR does not exist' do
    missing = File.join(@repo, 'missing')
    out, _err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => missing })
    expect(status.exitstatus).to eq(1)
    expect(out).to include("@@[error] Repository could not be found at: #{missing}")
  end

  it 'exits 1 when AC_TEMP_DIR is missing for a clone' do
    out, _err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/r.git' })
    expect(status.exitstatus).to eq(1)
    expect(out).to include('@@[error] Missing AC_TEMP_DIR')
  end
end

RSpec.describe 'end-to-end (subprocess, fake git, fixture scripts)' do
  around do |example|
    Dir.mktmpdir do |dir|
      @base = dir
      @git  = build_fake_git(dir)
      @repo = File.join(dir, 'repo')
      @temp = File.join(dir, 'temp')
      @env_file = File.join(dir, 'env')
      FileUtils.mkdir_p([@repo, @temp])
      example.run
    end
  end

  it 'runs a script from AC_SCRIPT_REPO_DIR with the extra parameters' do
    write_executable(File.join(@repo, 'run.sh'), %(#!/bin/sh\nfor a; do echo "arg=$a"; done\n))
    out, err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => @repo,
                                  'AC_SCRIPT_EXTRA_PARAMETERS' => 'one,"two words"' }, fake_bin: @git[:bin])
    expect(status.exitstatus).to eq(0), "stdout: #{out}\nstderr: #{err}"
    expect(out).to include("arg=one\narg=two words\n")
    expect(out).to include('Custom script execution completed successfully.')
    expect(File.read(@git[:log])).to eq("git rev-parse --abbrev-ref HEAD\n")
  end

  it 'checks out AC_SCRIPT_GIT_BRANCH before running' do
    write_executable(File.join(@repo, 'run.sh'), "#!/bin/sh\n")
    out, err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => @repo,
                                  'AC_SCRIPT_GIT_BRANCH' => 'develop' }, fake_bin: @git[:bin])
    expect(status.exitstatus).to eq(0), "stdout: #{out}\nstderr: #{err}"
    expect(File.read(@git[:log]).lines.map(&:chomp)).to eq(['git checkout develop', 'git rev-parse --abbrev-ref HEAD'])
  end

  it 'clones with masked credentials, runs the script and writes AC_SCRIPT_REPO_OUTPUT_DIR' do
    out, err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_CLONE_URL' => 'https://h/org/tools.git',
                                  'AC_SCRIPT_GIT_USERNAME' => 'u', 'AC_SCRIPT_GIT_PAT' => 'secret-pat',
                                  'AC_TEMP_DIR' => @temp, 'AC_ENV_FILE_PATH' => @env_file }, fake_bin: @git[:bin])
    expect(status.exitstatus).to eq(0), "stdout: #{out}\nstderr: #{err}"
    expect(out).to include('@@[command] git -c "http.extraheader=Authorization: Basic ******** clone https://h/org/tools.git')
    expect(out).not_to include(Base64.strict_encode64('u:secret-pat'))
    expect(out).to include('fixture ran')
    expect(File.read(@env_file)).to match(%r{\AAC_SCRIPT_REPO_OUTPUT_DIR=#{Regexp.escape(@temp)}/Cloned_Script_[^/]+/tools\n\z})
  end

  it 'exits non-zero when the script fails' do
    write_executable(File.join(@repo, 'run.sh'), "#!/bin/sh\necho 'script blew up' >&2\nexit 3\n")
    out, err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'run.sh', 'AC_SCRIPT_REPO_DIR' => @repo }, fake_bin: @git[:bin])
    expect(status.exitstatus).not_to eq(0)
    expect(err).to include('Command failed (3)', 'script blew up')
    expect(out).not_to include('completed successfully')
  end

  it 'exits 1 when the script file is not in the repository' do
    out, _err, status = run_main({ 'AC_SCRIPT_FILENAME' => 'missing.sh', 'AC_SCRIPT_REPO_DIR' => @repo }, fake_bin: @git[:bin])
    expect(status.exitstatus).to eq(1)
    expect(out).to include('@@[error] Script file not found at:')
  end
end

# ─── Coverage Report ──────────────────────────────────────────────────────────
def print_coverage_report
  result = Coverage.result
  lines  = result[MAIN_RB] || result[File.realpath(MAIN_RB)]
  return puts("\n  Coverage: main.rb was not tracked") if lines.nil?

  in_process = lines.compact.count(&:positive?)
  merged     = lines.dup
  runs       = 0
  Dir.glob(File.join(SUBPROCESS_COVERAGE_DIR, '*.json')).each do |file|
    sub = JSON.parse(File.read(file))
    next unless sub.is_a?(Array) && sub.size == merged.size

    runs += 1
    sub.each_with_index do |hits, i|
      next if hits.nil? || merged[i].nil?

      merged[i] += hits
    end
  end

  executable = merged.compact
  covered    = executable.count(&:positive?)
  total      = executable.size
  pct        = total.zero? ? 100.0 : (covered * 100.0 / total).round(1)
  color      = pct == 100 ? "\e[32;1m" : pct >= 80 ? "\e[33m" : "\e[31m"
  filled     = (pct / 5).round
  bar        = "\e[32m" + '█' * filled + "\e[90m" + '░' * (20 - filled) + "\e[0m"

  puts "\n\e[90m#{'═' * 72}\e[0m"
  puts '  Coverage Report'
  puts "\e[90m#{'─' * 72}\e[0m"
  puts "  main.rb  #{bar}  #{color}#{pct}%\e[0m  (#{covered}/#{total} lines)"
  puts "  \e[90m#{in_process} lines by in-process tests, #{runs} subprocess runs merged in\e[0m"
  missed = merged.each_with_index.select { |hits, _| hits&.zero? }.map { |_, i| i + 1 }
  unless missed.empty?
    ranges = missed.slice_when { |a, b| b != a + 1 }.map { |r| r.size == 1 ? r.first.to_s : "#{r.first}-#{r.last}" }
    puts "  Uncovered lines: \e[90m#{ranges.join(', ')}\e[0m"
  end
  puts "\e[90m#{'═' * 72}\e[0m"
rescue StandardError => e
  puts "\n  Coverage: unavailable (#{e.class}: #{e.message})"
end

# ─── Runner ───────────────────────────────────────────────────────────────────
if __FILE__ == $PROGRAM_NAME
  RSpec.configure do |config|
    config.add_formatter ReadableFormatter
    config.color = true
    config.order = :defined
  end

  exit_code = RSpec::Core::Runner.run(['--order', 'defined'])
  print_coverage_report
  FileUtils.rm_rf(STUB_LIB_DIR)
  exit exit_code
end
