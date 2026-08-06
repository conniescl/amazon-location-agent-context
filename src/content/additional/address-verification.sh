#!/bin/bash
# Address verification tips

ADDRESS_VERIFICATION_HEADER_NAME="Address Verification"

ADDRESS_VERIFICATION_HEADER_KEYWORDS="address verification, address validation, address standardization, bulk address validation, Jobs API, StartJob, ValidateAddress, GetJob, data cleansing"

ADDRESS_VERIFICATION_HEADER_WHEN="Verify and standardize addresses in bulk against authoritative postal data using the asynchronous Jobs API (StartJob with Action ValidateAddress), before persisting to databases or taking downstream actions"

# Read content from markdown file (avoids bash heredoc parsing issues)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDRESS_VERIFICATION_CONTENT="$(cat "$SCRIPT_DIR/../references/address-verification.md")"
