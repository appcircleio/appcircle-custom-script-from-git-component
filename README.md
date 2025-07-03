# Appcircle Custom Script from Git Component

Clone or use an existing Git repository, execute a specified custom script (bash, Python, Ruby, Node.js, Perl, or Java), and expose the workspace path via environment variables in your Appcircle workflow.

## Required Inputs

- `AC_SCRIPT_FILENAME`: Name of the script file to execute (e.g., build.sh, code.rb, test.py). Which is contained within the Git repository. The script file has to be under the root folder of the Git repository.

## Optional Inputs
One of the following input groups (either AC_SCRIPT_REPO_DIR or AC_SCRIPT_REPO_CLONE_URL, AC_SCRIPT_GIT_USERNAME, AC_SCRIPT_GIT_PAT) must be provided. If the repository is public, AC_SCRIPT_REPO_CLONE_URL is enough.
- `AC_SCRIPT_REPO_DIR`: Local directory path where your script already exists in the build machine for reuse in subsequent steps.
- `AC_SCRIPT_REPO_CLONE_URL`: Git clone URL of the repository containing your script.

- `AC_SCRIPT_GIT_USERNAME`: Username for private repository authentication. 
- `AC_SCRIPT_GIT_PAT`: Personal Access Token (PAT) for private repository authentication.

- `AC_SCRIPT_GIT_BRANCH`: Git branch to check out before execution (defaults to main).
- `AC_SCRIPT_EXTRA_PARAMETERS`: Additional parameters to pass to the script (comma "," separated; if a parameter has an empty character, define it with " ").

## Output Variable

- `AC_SCRIPT_REPO_OUTPUT_DIR`: To reuse the Git repository in subsequent steps, generate a local directory path key where your repository has been cloned in the build machine.