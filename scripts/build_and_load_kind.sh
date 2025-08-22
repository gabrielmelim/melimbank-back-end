#!/usr/bin/env bash
set -e
services=(customers-service accounts-service transactions-service ledger-service notifications-service gateway-service)
for s in "${services[@]}"; do
  echo "==> Building $s"
  (cd "$(dirname "$0")/../backend/services/$s" && ./mvnw -q -DskipTests package || mvn -q -DskipTests package)
  docker build -t $s:local "$(dirname "$0")/../backend/services/$s"
  kind load docker-image $s:local --name melimbank || echo "kind not available or cluster not named 'melimbank'"
done
echo "Done."
