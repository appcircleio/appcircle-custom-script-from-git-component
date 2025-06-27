#!/bin/bash
set -e

CS_GIT_CLONE_URL=""
CS_GIT_USERNAME=""
CS_GIT_PAT=""
CS_GIT_BRANCH=""
CS_GIT_SCRIPT_FILE=""

for i in "$@"
do
case $i in
    --scriptFile=*)
    CS_GIT_SCRIPT_FILE="${i#*=}"
    shift
    ;;
    --branch=*)
    CS_GIT_BRANCH="${i#*=}"
    shift
    ;;
    --gitURL=*)
    CS_GIT_CLONE_URL="${i#*=}"
    shift
    ;;
    --username=*)
    CS_GIT_USERNAME="${i#*=}"
    shift
    ;;
    --token=*)
    CS_GIT_PAT="${i#*=}"
    shift
    ;;
    *)
    ;;
esac
done

REQUIRED_VARS=("CS_GIT_CLONE_URL" "CS_GIT_USERNAME" "CS_GIT_PAT" "CS_GIT_BRANCH" "CS_GIT_SCRIPT_FILE")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Missing required argument: $var"
    exit 1
  fi
done

(
  AUTH_STRING="$CS_GIT_USERNAME:$CS_GIT_PAT"
  ENCODED_AUTH=$(printf "%s" "$AUTH_STRING" | base64)
  HEADER_VALUE="Authorization: Basic $ENCODED_AUTH"

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  CS_ROOT_FOLDER="Cloned_Script_$TIMESTAMP"
  mkdir -p "$CS_ROOT_FOLDER"
  cd "$CS_ROOT_FOLDER"

  echo "Cloning the repository..."
  git -c http.extraheader="$HEADER_VALUE" clone "$CS_GIT_CLONE_URL"

  CS_FOLDER_NAME=$(basename "$CS_GIT_CLONE_URL" .git)
  cd "$CS_FOLDER_NAME" || { echo "Failed to enter the directory."; exit 1; }

  git checkout "$CS_GIT_BRANCH"

  if [ ! -f "./$CS_GIT_SCRIPT_FILE" ]; then
      echo "Script file not found: $CS_GIT_SCRIPT_FILE"
      exit 1
  fi

  case "$CS_GIT_SCRIPT_FILE" in
    *.sh)
      chmod +x "./$CS_GIT_SCRIPT_FILE"
      ./"$CS_GIT_SCRIPT_FILE"
      ;;
    *.py)
      python "$CS_GIT_SCRIPT_FILE"
      ;;
    *.rb)
      ruby "$CS_GIT_SCRIPT_FILE"
      ;;
    *.pl)
      perl "$CS_GIT_SCRIPT_FILE"
      ;;
    *.js)
      node "$CS_GIT_SCRIPT_FILE"
      ;;
    *.java)
      java "$CS_GIT_SCRIPT_FILE"
      ;;
    *)
      echo "Unsupported script type: $CS_GIT_SCRIPT_FILE"
      exit 1
      ;;
  esac
)

exit 0
