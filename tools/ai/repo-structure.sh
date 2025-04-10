#!/usr/bin/env bash
# Generate repository structure for AI assistant memory
# Wraps output in <context name="directoryStructure"> tags.
# Hides dotfiles by default, use -a/--all to show them.

# Default settings
INCLUDE_HIDDEN=false
COPY_TO_CLIPBOARD=true

# Function to print usage
print_usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -a, --all         Include hidden files and directories (starting with '.')"
  echo "  -o, --output      Output to a file instead of stdout (e.g., -o structure.xml)"
  echo "  -h, --help        Show this help message"
}

# Parse arguments
OUTPUT_FILE=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -a|--all) INCLUDE_HIDDEN=true ;;
    -o|--output) OUTPUT_FILE="$2"; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
  esac
  shift
done

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: This script must be run from within a Git repository." >&2
  echo "Please navigate to your cloned Big-AGI repository and try again." >&2
  exit 1
fi


# Try to find the clipboard command for the current OS
clipboard_cmd=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  clipboard_cmd="pbcopy"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux with X11
  if command -v xclip &>/dev/null; then
    clipboard_cmd="xclip -selection clipboard"
  elif command -v xsel &>/dev/null; then
    clipboard_cmd="xsel --clipboard --input"
  fi
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  # Windows Git Bash or similar
  clipboard_cmd="clip"
fi


# Generate the structure
generate_structure() {
  # Use XML-like tags instead of markdown code fences
  echo '<context name="directoryStructure" description="Below is a snapshot of this project root file structure (git ls-files) at the start of the conversation. This snapshot will NOT update during the conversation.">'
  echo ""

  # Create a temporary file for the file list
  TMP_FILE=$(mktemp)

  # Get all Git-tracked files, filtering hidden ones if needed
  if [[ "$INCLUDE_HIDDEN" == false ]]; then
    # Filter out hidden files/dirs using grep -vE
    git ls-files | grep -vE '(^|/)\.' | sort > "$TMP_FILE"
  else
    # Include all files
    git ls-files | sort > "$TMP_FILE"
  fi

  # Check if TMP_FILE is empty after filtering
  if [[ ! -s "$TMP_FILE" ]]; then
      echo "# (No files found matching criteria)"
      rm "$TMP_FILE"
      echo '</context>' # Close the tag even if empty
      return
  fi

  # Initialize an associative array (requires bash 4+) for directories
  declare -A PROCESSED_DIRS

  # Process each file
  while IFS= read -r file; do
    # Skip empty lines
    if [[ -z "$file" ]]; then
      continue
    fi

    # Split the path into components
    IFS='/' read -ra PATH_PARTS <<< "$file"

    # Initialize directory tracking
    CURRENT_PATH=""
    PATH_LENGTH=${#PATH_PARTS[@]}

    # Process all directories in the path except the last part (which is the file)
    for ((i=0; i<PATH_LENGTH-1; i++)); do
      part=${PATH_PARTS[i]}
      if [[ -z "$CURRENT_PATH" ]]; then
        CURRENT_PATH="$part"
      else
        CURRENT_PATH="$CURRENT_PATH/$part"
      fi

      # Check if we've already processed this directory
      if [[ -z "${PROCESSED_DIRS[$CURRENT_PATH]}" ]]; then
        PROCESSED_DIRS["$CURRENT_PATH"]=1 # Mark as processed
        INDENT=$((i * 2)) # Indentation starts at 0 for the top level
        printf "%${INDENT}s- %s/\n" "" "$part"
      fi
    done

    # Output the file itself with proper indentation
    INDENT=$(((PATH_LENGTH - 1) * 2))
    printf "%${INDENT}s- %s\n" "" "${PATH_PARTS[-1]}"
  done < "$TMP_FILE"

  # Clean up
  rm "$TMP_FILE"

  # Close the XML-like tag
  echo '</context>'
}

# Check bash version for associative arrays
if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: This script requires Bash version 4 or higher for associative arrays." >&2
  exit 1
fi

# Handle output to file, clipboard, or stdout
if [[ -n "$OUTPUT_FILE" ]]; then
  generate_structure > "$OUTPUT_FILE"
  echo "Repository structure saved to $OUTPUT_FILE"

  if [[ "$COPY_TO_CLIPBOARD" == true ]]; then
    if [[ -n "$clipboard_cmd" ]]; then
      cat "$OUTPUT_FILE" | eval "$clipboard_cmd"
      echo "Also copied to clipboard!"
    else
      echo "Warning: Clipboard copy requested but no clipboard command found for your OS." >&2
    fi
  fi
elif [[ "$COPY_TO_CLIPBOARD" == true ]]; then
  if [[ -n "$clipboard_cmd" ]]; then
    generate_structure | tee >(eval "$clipboard_cmd" > /dev/null)
    echo -e "\nStructure copied to clipboard!"
  else
    echo "Warning: No clipboard command found for your OS. Displaying output instead." >&2
    generate_structure
  fi
else
  generate_structure
fi
