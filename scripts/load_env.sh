#!/bin/bash

function load_env() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

    # Source the .env file that lives next to this script (scripts/.env)
    ENV_FILE="$SCRIPT_DIR/.env"

    if [ ! -f "$ENV_FILE" ]; then
    echo "Error: expected env file at $ENV_FILE but it was not found." >&2
    echo "Create it (you can copy scripts/.env.example) and re-run the script." >&2
    exit 1
    fi

    source "$ENV_FILE"
    echo ".env file sourced successfully from: $ENV_FILE"
}