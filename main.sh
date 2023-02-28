#!/usr/bin/env bash

#######################################
# Echo error message.
# Arguments:
#   Message
# Outputs:
#   Writes ERROR: message to stdout.
#######################################
error_message() {
  echo -en "\033[31mERROR\033[0m: $1"
}

#######################################
# Echo warning message.
# Arguments:
#   Message.
# Outputs:
#   Writes WARNING: message to stdout.
#######################################
warning_message() {
  echo -en "\033[33mWARNING\033[0m: $1"
}

#######################################
# Echo info message.
# Arguments:
#   Message.
# Outputs:
#   Writes INFO: message to stdout.
#######################################
info_message() {
  echo -en "\033[32mINFO\033[0m: $1"
}

if [[ "$GITHUB_EVENT_NAME" != "pull_request" ]]; then
  echo $( warning_message "This action only runs on pull_request events." )
  echo $( info_message "Refer https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request for more information." )
  echo $( info_message "Exiting..." )

  exit 0
fi

if [[ $(cat "$GITHUB_EVENT_PATH" | jq -r .pull_request.body) == *"[do-not-scan]"* ]]; then
  echo $( info_message "[do-not-scan] found in PR description. Skipping PHPCS scan." )

  exit 0
fi

GITHUB_REPOSITORY_NAME=${GITHUB_REPOSITORY##*/}
GITHUB_REPOSITORY_OWNER=${GITHUB_REPOSITORY%%/*}
COMMIT_ID=$(cat $GITHUB_EVENT_PATH | jq -r '.pull_request.head.sha')

echo $( info_message "COMMIT_ID: $COMMIT_ID" )
echo $( info_message "GITHUB_REPOSITORY_NAME: $GITHUB_REPOSITORY_NAME" )
echo $( info_message "GITHUB_REPOSITORY_OWNER: $GITHUB_REPOSITORY_OWNER" )

if [[ -z "$GITHUB_REPOSITORY_NAME" ]] || [[ -z "$GITHUB_REPOSITORY_OWNER" ]] || [[ -z "$COMMIT_ID" ]]; then
  echo $( error_message "One or more of the following variables are not set: GITHUB_REPOSITORY_NAME, GITHUB_REPOSITORY_OWNER, COMMIT_ID" )

  exit 1
fi

if [[ -n "$VAULT_TOKEN" ]]; then
  GH_BOT_TOKEN=$(vault read -field=token secret/rtBot-token)
fi

if [[ -z "$GH_BOT_TOKEN" ]]; then
  echo $( error_message "GH_BOT_TOKEN is not set." )

  exit 1
fi

# Remove trailing and leading whitespaces.
GH_BOT_TOKEN=${GH_BOT_TOKEN//[[:blank:]]/}

IS_VALID_RES_CODE=$(wget --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer $GH_BOT_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/user -O /dev/null -q --server-response 2>&1 | awk '/^  HTTP/{print $2}'
)

if [[ "$IS_VALID_RES_CODE" != "200" ]]; then
  echo $( error_message "GH_BOT_TOKEN is not valid." )

  exit 1
fi

# VIP Go CI tools directory.
VIP_GO_CI_TOOLS_DIR="$ACTION_WORKDIR/vip-go-ci-tools"

# Setup GiHub workspace inside Docker container.
DOCKER_GITHUB_WORKSPACE="$ACTION_WORKDIR/workspace"

# Sync GitHub workspace to Docker GitHub workspace.
rsync -a "$GITHUB_WORKSPACE/" "$DOCKER_GITHUB_WORKSPACE"

echo $( info_message "DOCKER_GITHUB_WORKSPACE: $DOCKER_GITHUB_WORKSPACE" )

if [[ ! -d "$VIP_GO_CI_TOOLS_DIR" ]] || [[ ! -d "$DOCKER_GITHUB_WORKSPACE" ]]; then
  echo $( error_message "One or more of the following directories are not present: VIP_GO_CI_TOOLS_DIR, DOCKER_GITHUB_WORKSPACE" )

  exit 1
fi

################################################################################
#                    Configure options for vip-go-ci                           #
#                                                                              #
#   Refer https://github.com/Automattic/vip-go-ci#readme for more information  #
################################################################################

################################################################################
#                             General Configuration                            #
################################################################################

#######################################
# Set the --lint and --phpcs
# Default: true
# Options: BOOLEAN
#######################################
CMD=( "--lint=false" "--phpcs=true" )

#######################################
# Set the --skip-execution
# Default: false
# Options: BOOLEAN
#######################################
if [[ "$SKIP_EXECUTION" == "true" ]]; then
  CMD+=( "--skip-execution=true" )
fi

#######################################
# Set the --enforce-https-urls
# Default: true
# Options: BOOLEAN
#######################################
if [[ "$ENFORCE_HTTPS_URLS" == "false" ]]; then
  CMD+=( "--enforce-https-urls=false" )
fi

#######################################
# Set the --skip-draft-prs
# Default: false
# Options: BOOLEAN
#######################################
if [[ "$SKIP_DRAFT_PRS" == "true" ]]; then
  CMD+=( "--skip-draft-prs=true" )
fi

#######################################
# Set the --local-git-repo
# Options: STRING (Path to local git repo)
#######################################
local_git_repo="$DOCKER_GITHUB_WORKSPACE"

CMD+=( "--local-git-repo=$local_git_repo" )

#######################################
# Set the --name-to-use
# Default: 'rtBot'
# Options: STRING (Name to use for the bot)
#######################################
if [[ -n "$NAME_TO_USE" ]]; then
  name_to_use="$NAME_TO_USE"
else
  name_to_use="[action-phpcs-code-review](https://github.com/rtCamp/action-phpcs-code-review/)"
fi

CMD+=( "--name-to-use=$name_to_use" )

################################################################################
#                      Environmental & repo configuration                      #
################################################################################

#######################################
# Set the --env-options
# Default: ''
# Options: STRING (Comma separated list of options=env-var)
#######################################
if [[ -n "$ENV_OPTIONS" ]]; then
  CMD+=( "--env-options=$ENV_OPTIONS" )
fi

#######################################
# Set the --repo-options
# Default: false
# Options: BOOLEAN
#######################################
if [[ "$REPO_OPTIONS" == "true" ]]; then
  CMD+=( "--repo-options=true" )

  #######################################
  # Set the --repo-options-allowed
  # Default: All options are allowed.
  # Options: STRING (Comma separated list of allowed options)
  #######################################
  if [[ -n "$REPO_OPTIONS_ALLOWED" ]]; then
    CMD+=( "--repo-options-allowed=$REPO_OPTIONS_ALLOWED" )
  fi
fi

################################################################################
#                             GitHub configuration                             #
################################################################################

#######################################
# Set the --repo-owner
# Default: $GITHUB_REPOSITORY_OWNER
#######################################
repo_owner="$GITHUB_REPOSITORY_OWNER"

CMD+=( "--repo-owner=$repo_owner" )

#######################################
# Set the --repo-name
# Default: $GITHUB_REPOSITORY_NAME
#######################################
repo_name="$GITHUB_REPOSITORY_NAME"

CMD+=( "--repo-name=$repo_name" )

#######################################
# Set the --commit
# Default: $GITHUB_SHA
#######################################
commit="$COMMIT_ID"

CMD+=( "--commit=$commit" )

#######################################
# Set the --token
# Default: $GH_BOT_TOKEN
# Options: STRING (GitHub token)
#######################################
token="$GH_BOT_TOKEN"

CMD+=( "--token=$token" )

################################################################################
#                            PHPCS configuration                               #
################################################################################

#######################################
# Set the --phpcs
# Default: true
# Options: BOOLEAN
#######################################
if [[ "$PHPCS" == "false" ]]; then
  CMD+=( "--phpcs=false" )
fi

#######################################
# Set the --phpcs-php-path
# Default: PHP in $PATH
# Options: FILE (Path to php executable)
#######################################
if [[ -n "$PHPCS_PHP_PATH" ]]; then
  if [[ -z "$( command -v php$PHPCS_PHP_PATH )" ]]; then
    echo $( warning_message "php$PHPCS_PHP_PATH is not available. Using default php runtime...." )

    phpcs_php_path=$( command -v php )
  else
    phpcs_php_path=$( command -v php$PHPCS_PHP_PATH )
  fi

  CMD+=( "--phpcs-php-path=$phpcs_php_path" )
fi

#######################################
# Set the --phpcs-path
# Default: $VIP_GO_CI_TOOLS_DIR/phpcs/bin/phpcs
# Options: FILE (Path to phpcs executable)
#######################################
if [[ -z "$PHPCS_PATH" ]]; then
  phpcs_path="$VIP_GO_CI_TOOLS_DIR/phpcs/bin/phpcs"
else
  if [[ -f "$DOCKER_GITHUB_WORKSPACE/$PHPCS_PATH" ]]; then
    phpcs_path="$DOCKER_GITHUB_WORKSPACE/$PHPCS_PATH"
  else
    echo $( warning_message "$DOCKER_GITHUB_WORKSPACE/$PHPCS_PATH does not exist. Using default path...." )

    phpcs_path="$VIP_GO_CI_TOOLS_DIR/phpcs/bin/phpcs"
  fi
fi

# Keep PHPCS_FILE_PATH for backward compatibility.
if [[ -n "$PHPCS_FILE_PATH" ]]; then
  if [[ -f "$DOCKER_GITHUB_WORKSPACE/$PHPCS_FILE_PATH" ]]; then
    phpcs_path="$DOCKER_GITHUB_WORKSPACE/$PHPCS_FILE_PATH"
  else
    echo $( warning_message "$DOCKER_GITHUB_WORKSPACE/$PHPCS_FILE_PATH does not exist. Using default path...." )

    phpcs_path="$VIP_GO_CI_TOOLS_DIR/phpcs/bin/phpcs"
  fi
fi

CMD+=( "--phpcs-path=$phpcs_path" )

#######################################
# Set the --phpcs-standard
# Default: WordPress,WordPress-Core,WordPress-Docs,WordPress-Extra
# Options: STRING (Comma separated list of standards to check against)
#
#  1. Either a comma separated list of standards to check against.
#  2. Or a path to a custom ruleset.
#######################################
if [[ -n "$PHPCS_STANDARD" ]]; then
    if [[ -f "$DOCKER_GITHUB_WORKSPACE/$PHPCS_STANDARD" ]]; then
      phpcs_standard="$DOCKER_GITHUB_WORKSPACE/$PHPCS_STANDARD"
    else
      phpcs_standard="$PHPCS_STANDARD"
    fi
else
  phpcs_default_config_files=(
    '.phpcs.xml'
    'phpcs.xml'
    '.phpcs.xml.dist'
    'phpcs.xml.dist'
  )

  # If someone has passed standards as arguments, use those.
  if [[ -n "$1" ]]; then
    phpcs_standard="$1"
  else
    phpcs_standard='WordPress'
  fi

  for file in "${phpcs_default_config_files[@]}"; do
    if [[ -f "$DOCKER_GITHUB_WORKSPACE/$file" ]]; then
      phpcs_standard="$DOCKER_GITHUB_WORKSPACE/$file"
      break
    fi
  done
fi

# Keep PHPCS_STANDARD_FILE_NAME for backward compatibility
if [[ -n "$PHPCS_STANDARD_FILE_NAME" ]]; then
  if [[ -f "$DOCKER_GITHUB_WORKSPACE/$PHPCS_STANDARD_FILE_NAME" ]]; then
    phpcs_standard="$DOCKER_GITHUB_WORKSPACE/$PHPCS_STANDARD_FILE_NAME"
  else
    echo $( warning_message "$DOCKER_GITHUB_WORKSPACE/$PHPCS_STANDARD_FILE_NAME does not exist. Using default standards...." )
  fi
fi

CMD+=( "--phpcs-standard=$phpcs_standard" )

#######################################
# Set the --phpcs-standards-to-ignore
# Default: PHPCSUtils
# Options:String (Comma separated list of standards to ignore)
#######################################
if [[ -z "$PHPCS_STANDARDS_TO_IGNORE" ]]; then
  phpcs_standards_to_ignore='PHPCSUtils'
else
  phpcs_standards_to_ignore="$PHPCS_STANDARDS_TO_IGNORE"
fi

CMD+=( "--phpcs-standards-to-ignore=$phpcs_standards_to_ignore" )

#######################################
# Set the --phpcs-skip-scanning-via-labels-allowed
# Default: true
# Options: BOOLEAN
#######################################
phpcs_skip_scanning_via_labels_allowed='true'
if [[ "$PHPCS_SKIP_SCANNING_VIA_LABELS_ALLOWED" == "false" ]]; then
  phpcs_skip_scanning_via_labels_allowed='false'
fi

CMD+=( "--phpcs-skip-scanning-via-labels-allowed=$phpcs_skip_scanning_via_labels_allowed" )

#######################################
# Set the --phpcs-skip-folders
# Default: vendor,node_modules
# Options: STRING (Comma separated list of folders to skip)
#######################################
if [[ -z "$PHPCS_SKIP_FOLDERS" ]]; then
  phpcs_skip_folders='vendor,node_modules'
else
  phpcs_skip_folders="$PHPCS_SKIP_FOLDERS"
fi

# Keep SKIP_FOLDERS for backward compatibility
if [[ -n "$SKIP_FOLDERS" ]]; then
  if [[ -n "$phpcs_skip_folders" ]]; then
    phpcs_skip_folders="$phpcs_skip_folders,"
  fi

  phpcs_skip_folders="$phpcs_skip_folders$SKIP_FOLDERS"
fi

CMD+=( "--phpcs-skip-folders=$phpcs_skip_folders" )

#######################################
# Set the --phpcs-sniffs-exclude
# Default: ''
# Options: STRING (Comma separated list of sniffs to exclude)
#######################################
if [[ -n "$PHPCS_SNIFFS_EXCLUDE" ]]; then
  CMD+=( "--phpcs-sniffs-exclude=$PHPCS_SNIFFS_EXCLUDE" )
fi

#######################################
# Set the --phpcs-skip-folders-in-repo-options-file
# Default: true
# Options: BOOLEAN
#######################################
phpcs_skip_folders_in_repo_options_file='true'
if [[ "$PHPCS_SKIP_FOLDERS_IN_REPO_OPTIONS_FILE" == "false" ]]; then
  phpcs_skip_folders_in_repo_options_file="false"
fi

CMD+=( "--phpcs-skip-folders-in-repo-options-file=$phpcs_skip_folders_in_repo_options_file" )

################################################################################
#                GitHub reviews & generic comments configuration               #
################################################################################

#######################################
# Set the --report-no-issues-found
# Default: false
# Options: BOOLEAN
#######################################
report_no_issues_found='false'
if [[ "$REPORT_NO_ISSUES_FOUND" == "true" ]]; then
  report_no_issues_found='true'
fi

CMD+=( "--report-no-issues-found=$report_no_issues_found" )

#######################################
# Set the --review-comments-sort
# Default: true
# Options: BOOLEAN
#######################################
review_comments_sort='true'
if [[ "$REVIEW_COMMENTS_SORT" == "false" ]]; then
  review_comments_sort='false'
fi

CMD+=( "--review-comments-sort=$review_comments_sort" )

#######################################
# Set the --informational-msg
# Default: Powered by rtCamp's [GitHub Actions Library](https://github.com/rtCamp/github-actions-library/)
# Options: STRING (Message to be included in the comment)
#######################################
if [[ -z "$INFORMATIONAL_MSG" ]]; then
  informational_msg="Powered by rtCamp's [GitHub Actions Library](https://github.com/rtCamp/github-actions-library)"
else
  informational_msg="$INFORMATIONAL_MSG"
fi

CMD+=( "--informational-msg=$informational_msg" )

#######################################
# Set the --scan-details-msg-include
# Default: false
# Options: BOOLEAN
#######################################
scan_details_msg_include='false'
if [[ "$SCAN_DETAILS_MSG_INCLUDE" == "true" ]]; then
  scan_details_msg_include='true'
fi

CMD+=( "--scan-details-msg-include=$scan_details_msg_include" )

#######################################
# Set the --dismiss-stale-reviews
# Default: true
# Options: BOOLEAN
#######################################
dismiss_stale_reviews='true'
if [[ "$DISMISS_STALE_REVIEWS " == "false" ]]; then
  dismiss_stale_reviews='false'
fi

CMD+=( "--dismiss-stale-reviews=$dismiss_stale_reviews" )

################################################################################
#                Start Code Review and set GH build status                     #
################################################################################

echo $( info_message "Running PHPCS inspection..." )
echo $( info_message "Command: $VIP_GO_CI_TOOLS_DIR/vip-go-ci/vip-go-ci.php ${CMD[*]}" )

PHPCS_CMD=( php "$VIP_GO_CI_TOOLS_DIR/vip-go-ci/vip-go-ci.php" "${CMD[@]}" )

if [[ "$ENABLE_STATUS_CHECKS" == "true" ]]; then
  php $VIP_GO_CI_TOOLS_DIR/vip-go-ci/github-commit-status.php --repo-owner="$repo_owner" --repo-name="$repo_name" --github-token="$token" --github-commit="$commit" --build-context='PHPCS Code Review by rtCamp' --build-description="PR review in progress" --build-state="pending"

  "${PHPCS_CMD[@]}"

  export VIPGOCI_EXIT_CODE="$?"

  if [ "$VIPGOCI_EXIT_CODE" == "0" ] ; then
    export BUILD_STATE="success"
    export BUILD_DESCRIPTION="No PHPCS errors found"
  elif [ "$VIPGOCI_EXIT_CODE" == "230" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Pull request not found for commit"
  elif [ "$VIPGOCI_EXIT_CODE" == "248" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Commit not latest in PR"
  elif [ "$VIPGOCI_EXIT_CODE" == "249" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Inspection timed out, PR may be too large"
  elif [ "$VIPGOCI_EXIT_CODE" == "250" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Found PHPCS errors"
  elif [ "$VIPGOCI_EXIT_CODE" == "251" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Action is not configured properly"
  elif [ "$VIPGOCI_EXIT_CODE" == "252" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="GitHub communication error. Please retry"
  elif [ "$VIPGOCI_EXIT_CODE" == "253" ] ; then
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Wrong options passed to action"
  else
    export BUILD_STATE="failure"
    export BUILD_DESCRIPTION="Unknown error"
  fi

  php $VIP_GO_CI_TOOLS_DIR/vip-go-ci/github-commit-status.php --repo-owner="$repo_owner" --repo-name="$repo_name" --github-token="$token" --github-commit="$commit" --build-context='PHPCS Code Review by rtCamp' --build-description="$BUILD_DESCRIPTION" --build-state="$BUILD_STATE"
else
  "${PHPCS_CMD[@]}"
fi
