set shell := ["bash", "-euo", "pipefail", "-c"]

agentvm-test:
  bash tools/agentvm/tests/test_agentvm.sh

agentvm-integration-smoke:
  bash tools/agentvm/tests/integration_smoke.sh
