# Create the directory structure
mkdir -p .github/workflows

# Create the workflow file
cat > .github/workflows/monitor-zksealevel.yml << 'EOF'
name: Monitor zkSealevel Deployment

on:
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours
  workflow_dispatch:  # Manual trigger button

jobs:
  monitor:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout monitoring repo
        uses: actions/checkout@v4
      
      - name: Clone zkSealevel repo
        run: |
          git clone https://github.com/zkSLLabs/zkSealevel_Division_I.git
          cd zkSealevel_Division_I
          
      - name: Check for deployment signals
        id: check
        run: |
          cd zkSealevel_Division_I
          
          echo "## 🔍 zkSealevel Deployment Check" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Timestamp:** $(date -u)" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # Initialize alert flag
          ALERT=false
          
          # 1. Check cluster configuration
          echo "### 1️⃣ Cluster Configuration" >> $GITHUB_STEP_SUMMARY
          if grep -q 'cluster.*=.*"Devnet"' Anchor.toml 2>/dev/null; then
            echo "🚨 **CRITICAL: Switched to Devnet!**" >> $GITHUB_STEP_SUMMARY
            ALERT=true
            echo "alert=true" >> $GITHUB_OUTPUT
          else
            echo "✅ Still on Localnet" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 2. Check Program ID
          echo "### 2️⃣ Program ID Status" >> $GITHUB_STEP_SUMMARY
          if grep -q '^validator_lock.*=' Anchor.toml 2>/dev/null; then
            PROGRAM_ID=$(grep '^validator_lock' Anchor.toml | cut -d'"' -f2)
            echo "🚨 **Program ID Found:** \`$PROGRAM_ID\`" >> $GITHUB_STEP_SUMMARY
            echo "program_id=$PROGRAM_ID" >> $GITHUB_OUTPUT
            ALERT=true
          else
            echo "⏳ Program ID still commented out" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 3. Recent commits (last 24h)
          echo "### 3️⃣ Recent Activity (24h)" >> $GITHUB_STEP_SUMMARY
          RECENT_COUNT=$(git log --since="24 hours ago" --oneline | wc -l)
          echo "**Commits:** $RECENT_COUNT" >> $GITHUB_STEP_SUMMARY
          if [ $RECENT_COUNT -gt 0 ]; then
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
            git log --since="24 hours ago" --oneline | head -10 >> $GITHUB_STEP_SUMMARY
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 4. Deployment-related commits (7 days)
          echo "### 4️⃣ Deployment Signals (7 days)" >> $GITHUB_STEP_SUMMARY
          DEPLOY_COMMITS=$(git log --all --grep="deploy\|launch\|devnet\|release\|live" --since="7 days ago" --oneline | head -5)
          if [ -n "$DEPLOY_COMMITS" ]; then
            echo "🚨 **Found deployment-related commits:**" >> $GITHUB_STEP_SUMMARY
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
            echo "$DEPLOY_COMMITS" >> $GITHUB_STEP_SUMMARY
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
            ALERT=true
          else
            echo "✅ No deployment keywords in recent commits" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 5. Check for deployment branches
          echo "### 5️⃣ Deployment Branches" >> $GITHUB_STEP_SUMMARY
          DEPLOY_BRANCHES=$(git branch -r | grep -E "deploy|release|devnet|mainnet" || echo "none")
          if [ "$DEPLOY_BRANCHES" != "none" ]; then
            echo "🔀 **Found:**" >> $GITHUB_STEP_SUMMARY
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
            echo "$DEPLOY_BRANCHES" >> $GITHUB_STEP_SUMMARY
            echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
          else
            echo "✅ No deployment branches" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 6. Check for new tags
          echo "### 6️⃣ Latest Tag" >> $GITHUB_STEP_SUMMARY
          LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
          echo "**Tag:** $LATEST_TAG" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # 7. CI workflow changes
          echo "### 7️⃣ CI Changes" >> $GITHUB_STEP_SUMMARY
          if git diff HEAD~5 HEAD -- .github/workflows/ 2>/dev/null | grep -q "deploy" ; then
            echo "🚨 **CI deployment workflow modified!**" >> $GITHUB_STEP_SUMMARY
            ALERT=true
          else
            echo "✅ No recent CI changes" >> $GITHUB_STEP_SUMMARY
          fi
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # Final alert status
          if [ "$ALERT" = true ]; then
            echo "---" >> $GITHUB_STEP_SUMMARY
            echo "## 🚨 DEPLOYMENT ALERT!" >> $GITHUB_STEP_SUMMARY
            echo "One or more deployment signals detected. Check details above." >> $GITHUB_STEP_SUMMARY
          else
            echo "---" >> $GITHUB_STEP_SUMMARY
            echo "## ✅ No Immediate Deployment Signals" >> $GITHUB_STEP_SUMMARY
            echo "Continuing to monitor..." >> $GITHUB_STEP_SUMMARY
          fi
          
      - name: Create issue on alert
        if: steps.check.outputs.alert == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const programId = '${{ steps.check.outputs.program_id }}' || 'N/A';
            
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: '🚨 zkSealevel Deployment Alert - ' + new Date().toISOString().split('T')[0],
              body: `## Deployment Signals Detected!
              
              **Time:** ${new Date().toUTCString()}
              
              ### Actions Required:
              1. Check the [workflow run](https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}) for details
              2. Visit zkSealevel repo: https://github.com/zkSLLabs/zkSealevel_Division_I
              3. Verify deployment status
              
              ### Details:
              - Program ID: \`${programId}\`
              - Alert triggered by: Deployment signals in recent commits or configuration changes
              
              **This is an automated alert from the monitoring system.**`,
              labels: ['alert', 'deployment']
            })
            
      - name: Save monitoring data
        run: |
          cd zkSealevel_Division_I
          mkdir -p ../monitoring-data
          
          # Save snapshot
          echo "Timestamp: $(date -u)" > ../monitoring-data/latest.txt
          echo "Last commit: $(git log -1 --oneline)" >> ../monitoring-data/latest.txt
          echo "Cluster config:" >> ../monitoring-data/latest.txt
          grep "cluster" Anchor.toml >> ../monitoring-data/latest.txt || echo "Not found" >> ../monitoring-data/latest.txt
          
      - name: Upload monitoring data
        uses: actions/upload-artifact@v4
        with:
          name: monitoring-snapshot-${{ github.run_number }}
          path: monitoring-data/
          retention-days: 30
EOF

# Commit and push
git add .github/workflows/monitor-zksealevel.yml
git commit -m "Add zkSealevel monitoring workflow"
git push
```

---

## **Step 3: View the Output**

### **Option A: GitHub Actions UI (Recommended)**

1. **Go to your repository on GitHub:**
```
   https://github.com/YOUR_USERNAME/zkSealevel-monitor
```

2. **Click the "Actions" tab** at the top

3. **You'll see:**
   - Left sidebar: "Monitor zkSealevel Deployment" workflow
   - Main area: List of workflow runs

4. **To trigger manually (don't wait 4 hours):**
   - Click "Monitor zkSealevel Deployment" in left sidebar
   - Click "Run workflow" button (top right)
   - Click the green "Run workflow" button
   - Wait ~30 seconds

5. **View the results:**
   - Click on the running/completed workflow
   - Click on the "monitor" job
   - You'll see the output in the logs
   - **Most important:** Click the "Summary" tab at the top
   - This shows the formatted report!

### **Visual Guide to GitHub Actions Output:**
```
GitHub.com → Your Repo → Actions Tab
├── Workflow runs (list)
│   ├── ✅ Monitor zkSealevel Deployment #1
│   │   ├── Summary (← CHECK HERE!)
│   │   │   └── 🔍 Formatted deployment check
│   │   ├── Jobs
│   │   │   └── monitor
│   │   │       ├── Checkout monitoring repo
│   │   │       ├── Clone zkSealevel repo
│   │   │       └── Check for deployment signals (← Detailed logs)
│   │   └── Artifacts
│   │       └── monitoring-snapshot-1.zip (← Download data)
