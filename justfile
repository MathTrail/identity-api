# MathTrail Identity Stack

set shell := ["bash", "-c"]

NAMESPACE := "mathtrail"
SERVICE := "identity-ui"
CHART_NAME := "identity-ui"

# -- Development ---------------------------------------------------------------

# One-time setup: add Helm repos
setup:
    helm repo add mathtrail-charts https://MathTrail.github.io/charts/charts 2>/dev/null || true
    helm repo update

# Start development mode with hot-reload and port-forwarding
dev: setup
    skaffold dev --port-forward

# Build and deploy to cluster (all Ory components + Identity UI)
deploy: setup
    skaffold run

# Remove everything from cluster
delete:
    skaffold delete

# View Identity UI pod logs
logs:
    kubectl logs -l app.kubernetes.io/name={{ SERVICE }} -n {{ NAMESPACE }} -f

# Check deployment status for all identity components
status:
    #!/bin/bash
    set -e
    echo "=== Ory Components ==="
    kubectl get pods -n {{ NAMESPACE }} | grep -E "kratos|hydra|keto|oathkeeper" || echo "No Ory pods found"
    echo ""
    echo "=== Identity UI ==="
    kubectl get pods -n {{ NAMESPACE }} -l app.kubernetes.io/name={{ SERVICE }}
    echo ""
    echo "=== Services ==="
    kubectl get svc -n {{ NAMESPACE }} | grep -E "kratos|hydra|keto|oathkeeper|identity" || echo "No identity services found"

# -- Testing -------------------------------------------------------------------

# Create a test user via Kratos Admin API
create-test-user:
    #!/bin/bash
    set -e
    echo "Creating test user..."
    curl -s -X POST http://localhost:4434/admin/identities \
      -H "Content-Type: application/json" \
      -d '{
        "schema_id": "mathtrail-user",
        "traits": {
          "email": "teacher@mathtrail.test",
          "name": { "first": "Test", "last": "Teacher" },
          "role": "teacher",
          "school_context": { "school_id": "school-1", "class_id": "math-101" }
        },
        "credentials": {
          "password": { "config": { "password": "test1234!" } }
        }
      }' | jq .
    echo "Test user created"

# -- Monitoring Access (Keto) --------------------------------------------------

# Grant a user access to Grafana and Pyroscope via Oathkeeper
# Usage: just grant-monitoring <kratos-user-uuid>
grant-monitoring USER_ID:
    #!/bin/bash
    set -e
    echo "Granting monitoring access to {{ USER_ID }}..."
    curl -sf -X PUT http://localhost:4467/admin/relation-tuples \
      -H "Content-Type: application/json" \
      -d '{
        "namespace": "Monitoring",
        "object": "ui",
        "relation": "viewer",
        "subject_id": "{{ USER_ID }}"
      }' | jq .
    echo "Done. User can now access /observability/grafana/ and /observability/pyroscope/"

# Revoke monitoring access from a user
# Usage: just revoke-monitoring <kratos-user-uuid>
revoke-monitoring USER_ID:
    #!/bin/bash
    set -e
    echo "Revoking monitoring access from {{ USER_ID }}..."
    curl -sf -X DELETE \
      "http://localhost:4467/admin/relation-tuples?namespace=Monitoring&object=ui&relation=viewer&subject_id={{ USER_ID }}"
    echo "Done."

# Check if a user has monitoring access (returns {allowed: true/false})
# Usage: just check-monitoring <kratos-user-uuid>
check-monitoring USER_ID:
    curl -sf -X POST http://localhost:4466/relation-tuples/check \
      -H "Content-Type: application/json" \
      -d '{
        "namespace": "Monitoring",
        "object": "ui",
        "relation": "viewer",
        "subject_id": "{{ USER_ID }}"
      }' | jq .

# List all users with monitoring access
list-monitoring:
    curl -sf "http://localhost:4466/admin/relation-tuples?namespace=Monitoring&object=ui&relation=viewer" | jq '.relation_tuples[].subject_id'

# Add a Keto relation tuple (teacher -> class)
add-test-relation:
    #!/bin/bash
    set -e
    echo "Adding test relation..."
    curl -s -X PUT http://localhost:4467/admin/relation-tuples \
      -H "Content-Type: application/json" \
      -d '{
        "namespace": "ClassGroup",
        "object": "math-101",
        "relation": "teachers",
        "subject_id": "test-teacher-uuid"
      }' | jq .
    echo "Relation added"

# Test Identity UI endpoints
test:
    #!/bin/bash
    set -e
    echo "Testing Identity UI..."
    echo ""
    echo "Testing /health/ready..."
    curl -s http://localhost:8090/health/ready | jq .
    echo ""
    echo "Testing /auth/login (HTTP status)..."
    curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/auth/login
    echo ""

# -- Chart Release -------------------------------------------------------------

# Package and publish chart to mathtrail-charts
release-chart:
    #!/bin/bash
    set -e
    CHART_DIR="infra/helm/{{ CHART_NAME }}"
    VERSION=$(grep '^version:' "$CHART_DIR/Chart.yaml" | awk '{print $2}')
    echo "Packaging {{ CHART_NAME }} v${VERSION}..."
    helm package "$CHART_DIR" --destination /tmp/mathtrail-charts

    CHARTS_REPO="/tmp/mathtrail-charts-repo"
    rm -rf "$CHARTS_REPO"
    git clone git@github.com:MathTrail/charts.git "$CHARTS_REPO"
    cp /tmp/mathtrail-charts/{{ CHART_NAME }}-*.tgz "$CHARTS_REPO/charts/"
    cd "$CHARTS_REPO"
    helm repo index ./charts \
        --url https://MathTrail.github.io/charts/charts
    git add charts/
    git commit -m "chore: release {{ CHART_NAME }} v${VERSION}"
    git push
    echo "Published {{ CHART_NAME }} v${VERSION} to mathtrail-charts"

# -- Terraform -----------------------------------------------------------------

# Initialize Terraform for an environment
tf-init ENV:
    cd infra/terraform/environments/{{ ENV }} && terraform init

# Plan Terraform changes
tf-plan ENV:
    cd infra/terraform/environments/{{ ENV }} && terraform plan

# Apply Terraform changes
tf-apply ENV:
    cd infra/terraform/environments/{{ ENV }} && terraform apply

# -- On-prem Node Preparation -------------------------------------------------

# Prepare an Ubuntu node for on-prem deployment
prepare-node IP:
    cd infra/ansible && ansible-playbook \
        -i "{{ IP }}," \
        playbooks/setup.yml
