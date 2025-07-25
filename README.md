# Appcircle Custom Script from Git Component

Clone a Git repository from a remote source or use a repository that already exists on the local machine, execute a specified custom script (Bash, Python, Ruby, Node.js, Perl, or Java), and expose the workspace path via environment variables in your Appcircle workflow.

## Required Inputs

- `AC_SCRIPT_FILENAME`: Name of the script file to execute (e.g., `build.sh`, `code.rb`, `test.py`). Which is contained within the Git repository.

## Optional Inputs
One of the following input groups (either `AC_SCRIPT_REPO_DIR` or `AC_SCRIPT_REPO_CLONE_URL`, `AC_SCRIPT_GIT_USERNAME`, `AC_SCRIPT_GIT_PAT`) must be provided. If the repository is public, `AC_SCRIPT_REPO_CLONE_URL` is enough.
- `AC_SCRIPT_REPO_DIR`: If the Git repository has already been cloned in a previous step of the same workflow, set the Repository Directory Output here. This input is required if `Git Clone URL` is not provided.
- `AC_SCRIPT_REPO_CLONE_URL`: Git repository clone URL (https). Required if the Repository Directory Output is not provided. (e.g. https://exampleGit.exampleRepo.git).

- `AC_SCRIPT_GIT_USERNAME`: Git provider username for authentication. This is required if the Repository Directory input is not provided. A public repository does not require a username.
- `AC_SCRIPT_GIT_PAT`: Git provider personal access token for authentication. Required if the `Repository Directory` input is not provided. A public repository does not require a PAT.

- `AC_SCRIPT_GIT_BRANCH`: Name of the branch to check out from the script repository. If not specified, the repository's default branch will be used.
- `AC_SCRIPT_EXTRA_PARAMETERS`: Additional parameters to pass to the script (comma "," separated; if a parameter has an empty character, define it with " "; e.g. `param1,param2,"string with spaces",param3`).

## Output Variable

- `AC_SCRIPT_REPO_OUTPUT_DIR`: Specifies a local directory path where the Git repository is cloned on the runner. This allows reusing the same repository in subsequent steps of the workflow.