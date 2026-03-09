#!/bin/bash
# =============================================================================
# GitHub Projects V2 Helper Functions
# =============================================================================
# Shared functions for syncing issues/PRs with GitHub Projects V2.
# Used by project-sync.yml workflow.
#
# Required environment variables:
#   GH_TOKEN        — GitHub token with project + repo scope
#   PROJECT_OWNER   — Owner of the project (GitHub username or org)
#   PROJECT_NUMBER  — Project number (from the project URL)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Project Data (cached via temp file to survive subshells)
# ---------------------------------------------------------------------------
_PROJECT_CACHE_FILE="${TMPDIR:-/tmp}/.gh-project-cache-$$"
trap 'rm -f "$_PROJECT_CACHE_FILE"' EXIT

fetch_project_data() {
  if [ -f "$_PROJECT_CACHE_FILE" ]; then
    cat "$_PROJECT_CACHE_FILE"
    return 0
  fi

  local result project_data

  result=$(gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      organization(login: $owner) {
        projectV2(number: $number) {
          id
          field(name: "Status") {
            ... on ProjectV2SingleSelectField {
              id
              options { id name }
            }
          }
        }
      }
    }' -f owner="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" 2>/dev/null || echo '{}')

  project_data=$(echo "$result" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null)

  if [ -z "$project_data" ] || [ "$project_data" = "null" ]; then
    result=$(gh api graphql -f query='
      query($owner: String!, $number: Int!) {
        user(login: $owner) {
          projectV2(number: $number) {
            id
            field(name: "Status") {
              ... on ProjectV2SingleSelectField {
                id
                options { id name }
              }
            }
          }
        }
      }' -f owner="$PROJECT_OWNER" -F number="$PROJECT_NUMBER")

    project_data=$(echo "$result" | jq -r '.data.user.projectV2')
  fi

  if [ -z "$project_data" ] || [ "$project_data" = "null" ]; then
    echo "::error::Could not find project #$PROJECT_NUMBER for owner $PROJECT_OWNER"
    return 1
  fi

  echo "$project_data" > "$_PROJECT_CACHE_FILE"
  echo "$project_data"
}

get_project_id() {
  fetch_project_data | jq -r '.id'
}

get_status_field_id() {
  fetch_project_data | jq -r '.field.id'
}

get_status_option_id() {
  local status_name="$1"
  fetch_project_data | jq -r --arg name "$status_name" \
    '.field.options[] | select(.name == $name) | .id'
}

# ---------------------------------------------------------------------------
# Project Item Operations
# ---------------------------------------------------------------------------

add_to_project() {
  local content_id="$1"
  local project_id
  project_id=$(get_project_id)

  local result
  result=$(gh api graphql -f query='
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(input: {
        projectId: $projectId
        contentId: $contentId
      }) {
        item { id }
      }
    }' -f projectId="$project_id" -f contentId="$content_id")

  echo "$result" | jq -r '.data.addProjectV2ItemById.item.id'
}

get_item_id_for_content() {
  local content_id="$1"
  local project_id
  project_id=$(get_project_id)

  local result
  result=$(gh api graphql -f query='
    query($id: ID!) {
      node(id: $id) {
        ... on Issue {
          projectItems(first: 50) {
            nodes { id project { id } }
          }
        }
        ... on PullRequest {
          projectItems(first: 50) {
            nodes { id project { id } }
          }
        }
      }
    }' -f id="$content_id")

  echo "$result" | jq -r --arg pid "$project_id" \
    '[.data.node.projectItems.nodes[] | select(.project.id == $pid) | .id] | first // empty'
}

set_status() {
  local item_id="$1"
  local status_name="$2"
  local project_id field_id option_id

  project_id=$(get_project_id)
  field_id=$(get_status_field_id)
  option_id=$(get_status_option_id "$status_name")

  if [ -z "$option_id" ] || [ "$option_id" = "null" ]; then
    echo "::error::Status option '$status_name' not found in project. Available options:"
    fetch_project_data | jq -r '.field.options[].name'
    return 1
  fi

  gh api graphql -f query='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $projectId
        itemId: $itemId
        fieldId: $fieldId
        value: { singleSelectOptionId: $optionId }
      }) {
        projectV2Item { id }
      }
    }' -f projectId="$project_id" \
       -f itemId="$item_id" \
       -f fieldId="$field_id" \
       -f optionId="$option_id" > /dev/null

  echo "✓ Item moved to '$status_name'"
}

# ---------------------------------------------------------------------------
# Compound Operations
# ---------------------------------------------------------------------------

add_and_set_status() {
  local content_id="$1"
  local status_name="$2"
  local item_id

  item_id=$(add_to_project "$content_id")

  if [ -n "$item_id" ] && [ "$item_id" != "null" ]; then
    set_status "$item_id" "$status_name"
  else
    echo "::error::Failed to add item to project"
    return 1
  fi
}

ensure_status() {
  local content_id="$1"
  local status_name="$2"
  local item_id

  item_id=$(get_item_id_for_content "$content_id")

  if [ -z "$item_id" ] || [ "$item_id" = "null" ]; then
    echo "Item not in project, adding first..."
    item_id=$(add_to_project "$content_id")
  fi

  if [ -n "$item_id" ] && [ "$item_id" != "null" ]; then
    set_status "$item_id" "$status_name"
  else
    echo "::error::Could not find or add item to project"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Issue Number Extraction
# ---------------------------------------------------------------------------

extract_issue_number_from_branch() {
  local branch="$1"

  if [[ "$branch" =~ issue[/-]([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ ^([0-9]+)[/-] ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ [/-]([0-9]+)[/-] ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ [/-]([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

extract_issue_numbers_from_body() {
  local body="$1"
  if [ -z "$body" ]; then
    echo ""
    return 0
  fi
  echo "$body" | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#[0-9]+' \
    | grep -oE '[0-9]+' \
    | sort -un \
    || echo ""
}

get_linked_issue_numbers() {
  local pr_number="$1"
  local owner="$2"
  local repo="$3"
  local branch="$4"
  local body="$5"
  local issues=""

  issues=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          closingIssuesReferences(first: 10) {
            nodes { number }
          }
        }
      }
    }' -f owner="$owner" -f repo="$repo" -F number="$pr_number" \
    --jq '.data.repository.pullRequest.closingIssuesReferences.nodes[].number' 2>/dev/null || echo "")

  if [ -z "$issues" ] && [ -n "$body" ]; then
    issues=$(extract_issue_numbers_from_body "$body")
  fi

  if [ -z "$issues" ] && [ -n "$branch" ]; then
    local branch_issue
    branch_issue=$(extract_issue_number_from_branch "$branch")
    if [ -n "$branch_issue" ]; then
      issues="$branch_issue"
    fi
  fi

  echo "$issues"
}

get_issue_node_id() {
  local issue_number="$1"
  local owner="$2"
  local repo="$3"

  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) { id }
      }
    }' -f owner="$owner" -f repo="$repo" -F number="$issue_number" \
    --jq '.data.repository.issue.id' 2>/dev/null || echo ""
}
