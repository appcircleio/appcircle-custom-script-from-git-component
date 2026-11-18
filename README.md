# Appcircle Custom Script from Git Component

Clone a Git repository from a remote source or use a repository that already exists on the local machine, execute a specified custom script (Bash, Python, Ruby, Node.js, Perl, or Java), and expose the workspace path via environment variables in your Appcircle workflow.

## Required Inputs

- `AC_SCRIPT_FILENAME`: Specifies the exact name of the script file to execute within the Git repository (e.g., `test.sh`, `code.rb` or `relative_path/python.py`).

## Optional Inputs

- `AC_SCRIPT_REPO_DIR`: If the Git repository has already been cloned in a previous step of the same workflow, set the Repository Directory Output here. This input is required if `AC_SCRIPT_REPO_CLONE_URL` is not provided.
- `AC_SCRIPT_REPO_CLONE_URL`: Git repository clone URL. Required if the Repository Directory Output is not provided. (e.g. https://exampleGit.exampleRepo.git). This input is required if `AC_SCRIPT_REPO_DIR` is not provided.

- `AC_SCRIPT_GIT_USERNAME`: Git provider username for authentication. This is required if the `AC_SCRIPT_REPO_DIR` input is not provided and the Git repository is private.
- `AC_SCRIPT_GIT_PAT`: Git provider personal access token for authentication. This is required if the `AC_SCRIPT_REPO_DIR` input is not provided and the Git repository is private.

- `AC_SCRIPT_GIT_BRANCH`: Name of the branch to check out from the script repository. If not specified, the repository's default branch will be used.
- `AC_SCRIPT_EXTRA_PARAMETERS`: Additional parameters to pass to the script (comma "," separated; if a parameter has an empty character, define it with " "; e.g. `param1,param2,"param3 with spaces",param4`).

## Output Variable

- `AC_SCRIPT_REPO_OUTPUT_DIR`: Specifies a local directory path where the Git repository is cloned on the runner. This allows reusing the same repository in subsequent steps of the workflow.

## Running tests

Requires the [RSpec](https://rspec.info) gem and the Ruby standard library (Coverage, Open3). No Gemfile or Bundler needed.

```bash
ruby test/test_main.rb
```

Tests never touch the network or execute a real toolchain: helpers that shell out are verified by asserting the composed command, and subprocess tests run `main.rb` against a fake `git` on `PATH` with fixture scripts inside a temporary directory. The `colored` gem is stubbed automatically when it is not installed. A coverage report is printed at the end of each run.
