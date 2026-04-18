# 🔑 Google Analytics Setup Guide

## ⏱️ Estimated Time: 10-15 minutes

This guide walks you through setting up Google Analytics credentials for the daily analytics feature. Follow each step in order.

## 📋 Prerequisites

- A Google Analytics 4 (GA4) property for your website
- Access to the Google Cloud Console
- Admin access to this GitHub repository (to add secrets)

## 🔧 Step 1: Find Your GA4 Property ID

1. Open [Google Analytics](https://analytics.google.com/)
2. Select your property from the dropdown at the top left
3. Click **Admin** (gear icon at bottom left)
4. Under **Property Settings**, find your **Property ID** — it's a numeric value like `123456789`
5. Copy this number — you'll need it in Step 4

## ☁️ Step 2: Create a GCP Service Account

1. Open the [Google Cloud Console](https://console.cloud.google.com/)
2. Select or create a project — [Create a new project](https://console.cloud.google.com/projectcreate) if needed
3. Enable the **Google Analytics Data API**:
   - Go to [API Library](https://console.cloud.google.com/apis/library)
   - Search for "Google Analytics Data API"
   - Or go directly to: [Enable Google Analytics Data API](https://console.cloud.google.com/apis/library/analyticsdata.googleapis.com)
   - Click **Enable**
4. Create a service account:
   - Go to [Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
   - Click **Create Service Account**
   - Name: `analytics-reader` (or any name you prefer)
   - Click **Create and Continue**
   - For role, select **Viewer** (or skip — we'll grant analytics access separately)
   - Click **Done**
5. Create a key for the service account:
   - Click on the service account you just created
   - Go to the **Keys** tab
   - Click **Add Key** → **Create new key**
   - Select **JSON** format
   - Click **Create** — a JSON file will download
   - Keep this file safe — you'll need the contents in Step 4

## 📊 Step 3: Grant Analytics Access to the Service Account

1. Open [Google Analytics](https://analytics.google.com/)
2. Click **Admin** (gear icon at bottom left)
3. Under **Property**, click **Property Access Management**
4. Click the **+** button → **Add users**
5. Enter the service account email (looks like `analytics-reader@your-project.iam.gserviceaccount.com`)
   - You can find this email in the JSON key file under the `client_email` field
6. Set role to **Viewer** (read-only access is all we need)
7. Uncheck "Notify new users by email" (service accounts don't have email)
8. Click **Add**

## 🔐 Step 4: Add GitHub Repository Secrets

1. Go to your repository's [Settings → Secrets and variables → Actions](https://github.com/bagrounds/obsidian-github-publisher-sync/settings/secrets/actions)
2. Add two new **repository secrets**:

### GA_PROPERTY_ID
- Click **New repository secret**
- Name: `GA_PROPERTY_ID`
- Value: Your GA4 property ID from Step 1 (e.g., `123456789`)
- Click **Add secret**

### GCP_SERVICE_ACCOUNT_KEY
- Click **New repository secret**
- Name: `GCP_SERVICE_ACCOUNT_KEY`
- Value: The **entire contents** of the JSON key file from Step 2
  - Open the downloaded JSON file in a text editor
  - Select all (Ctrl+A / Cmd+A) and copy (Ctrl+C / Cmd+C)
  - Paste the full JSON into the secret value field
- Click **Add secret**

## ✅ Step 5: Verify the Integration

The daily analytics task runs at 1 AM Pacific time. To test immediately:

1. Go to [Actions → All Scheduled Tasks](https://github.com/bagrounds/obsidian-github-publisher-sync/actions/workflows/scheduled.yml)
2. Click **Run workflow**
3. Set task to: `daily-analytics`
4. Set hour to: `1` (to match the schedule)
5. Click **Run workflow**
6. Check the workflow logs for analytics output:
   - Success: `📊 Analytics for YYYY-MM-DD: X users, Y views, Z sessions`
   - Disabled: `⚠️ GA_PROPERTY_ID not set — daily analytics disabled` (if secrets not configured)
   - Auth error: `❌ Failed to get access token: ...` (check service account setup)
   - API error: `GA API HTTP 403: ...` (check property access in Step 3)
   - No data: `No analytics data returned` (check property ID is correct)

## 🔍 Troubleshooting

### Common Issues

**"Failed to get access token"**
- Verify the JSON key content was pasted completely (including the curly braces)
- Check that the Google Analytics Data API is enabled in GCP
- Ensure the service account belongs to the correct GCP project

**"GA API returned status 403"**
- The service account doesn't have access to the GA4 property
- Go back to Step 3 and verify the service account email was added with Viewer access
- Wait a few minutes — permission changes can take time to propagate

**"GA API returned status 400"**
- The property ID might be incorrect
- Verify it's the numeric GA4 property ID (not the measurement ID like G-XXXXXXXXXX)

**"No reflection for YYYY-MM-DD, skipping analytics"**
- The daily reflection note hasn't been created yet for yesterday
- Blog series tasks create reflections — ensure at least one blog series has run

## 🗑️ Cleanup

- The downloaded JSON key file can be deleted from your computer after adding it as a GitHub secret
- If you need to revoke access later, delete the key from the GCP service account page
