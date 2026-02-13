# MathTrail Identity Stack

set shell := ["bash", "-c"]

NAMESPACE := "mathtrail"
SERVICE := "identity-ui"

# One-time setup: add Helm repos
setup:
    helm repo add mathtrail-charts https://RyazanovAlexander.github.io/mathtrail-charts/charts 2>/dev/null || true
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
