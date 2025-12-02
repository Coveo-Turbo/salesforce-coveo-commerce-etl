#!/usr/bin/env bash
set -euo pipefail

# Script to update README.md with installation instructions
# Environment variables required:
#   VERSION - Package version (e.g., 1.2.0)
#   REPO_URL - GitHub repository URL (e.g., https://github.com/owner/repo)

if [ -z "${VERSION:-}" ]; then
  echo "Error: VERSION environment variable is required"
  exit 1
fi

if [ -z "${REPO_URL:-}" ]; then
  echo "Error: REPO_URL environment variable is required"
  exit 1
fi

RELEASE_DATE=$(date +"%Y-%m-%d")
RELEASE_TAG="v${VERSION}"
DOWNLOAD_URL="${REPO_URL}/releases/download/${RELEASE_TAG}/salesforce-coveo-commerce-etl-${RELEASE_TAG}.zip"

# Create temporary file for the installation section
INSTALL_FILE=$(mktemp)
cat > "$INSTALL_FILE" << EOF
## 📥 Installation

### Current Version: ${VERSION}

> **Released:** ${RELEASE_DATE}

### Option 1: Deploy via Salesforce CLI (Recommended)

1. **Download the latest release:**
   \`\`\`bash
   curl -L -o coveo-etl.zip "${DOWNLOAD_URL}"
   unzip coveo-etl.zip -d coveo-etl
   \`\`\`

2. **Deploy to your Salesforce org:**
   \`\`\`bash
   sf project deploy start --metadata-dir coveo-etl --target-org <your-org-alias>
   \`\`\`

3. **Assign the permission set:**
   \`\`\`bash
   sf org assign permset --name CoveoETL_Admin --target-org <your-org-alias>
   \`\`\`

### Option 2: Deploy from Source

1. **Clone this repository:**
   \`\`\`bash
   git clone ${REPO_URL}.git
   cd salesforce-coveo-commerce-etl
   \`\`\`

2. **Deploy to your org:**
   \`\`\`bash
   sf project deploy start --target-org <your-org-alias>
   \`\`\`

3. **Assign the permission set:**
   \`\`\`bash
   sf org assign permset --name CoveoETL_Admin --target-org <your-org-alias>
   \`\`\`

### Post-Installation Setup

After installation, complete the following steps:

1. **Configure Named Credential:**
   - Navigate to **Setup → Named Credentials**
   - Create or update the \`Coveo_Push\` Named Credential
   - Set the URL to your Coveo Push API endpoint (e.g., \`https://api.cloud.coveo.com/push/v1\`)
   - Configure the External Credential with your Coveo API Key

2. **Configure Catalog Jobs:**
   - Go to **Setup → Custom Metadata Types → Catalog Job Configurations**
   - Create configuration records for each catalog you want to export

3. **Access the Admin Console:**
   - Navigate to \`/lightning/n/Coveo_ETL_Setup\` in your Salesforce org

For detailed configuration instructions, see the [Configuration](#%EF%B8%8F-configuration) section below.

---

EOF

# Create output file
OUTPUT_FILE=$(mktemp)

# Check if Installation section exists
if grep -q "^## 📥 Installation" README.md; then
  echo "Updating existing Installation section..."
  
  # Process the README: remove old Installation section and add new one
  awk '
    BEGIN { skip=0; printed=0 }
    /^## 📥 Installation/ { skip=1; next }
    /^---$/ && skip { skip=0; next }
    /^# 🚀 Features/ && !printed {
      while ((getline line < "'"$INSTALL_FILE"'") > 0) print line
      printed=1
    }
    !skip { print }
  ' README.md > "$OUTPUT_FILE"
else
  echo "Adding new Installation section..."
  
  # Add Installation section before Features section
  awk '
    BEGIN { printed=0 }
    /^# 🚀 Features/ && !printed {
      while ((getline line < "'"$INSTALL_FILE"'") > 0) print line
      printed=1
    }
    { print }
  ' README.md > "$OUTPUT_FILE"
fi

# Replace the original README
mv "$OUTPUT_FILE" README.md

# Cleanup
rm -f "$INSTALL_FILE"

echo "README.md updated with installation instructions for version ${VERSION}"
