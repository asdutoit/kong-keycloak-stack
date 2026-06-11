#!/bin/bash

KONG_ADMIN="http://localhost:8001"

echo "Kong API Key Management"
echo "======================"

case "$1" in
  "create-consumer")
    curl -X POST $KONG_ADMIN/consumers --data "username=$2"
    ;;
  "create-key")
    if [ -z "$3" ]; then
      # Auto-generate key
      curl -X POST $KONG_ADMIN/consumers/$2/key-auth
    else
      # Use provided key
      curl -X POST $KONG_ADMIN/consumers/$2/key-auth --data "key=$3"
    fi
    ;;
  "list-keys")
    curl -X GET $KONG_ADMIN/consumers/$2/key-auth
    ;;
  "delete-key")
    curl -X DELETE $KONG_ADMIN/consumers/$2/key-auth/$3
    ;;
  "list-consumers")
    curl -X GET $KONG_ADMIN/consumers
    ;;
  *)
    echo "Usage: $0 {create-consumer|create-key|list-keys|delete-key|list-consumers}"
    echo ""
    echo "Examples:"
    echo "  $0 create-consumer myuser"
    echo "  $0 create-key myuser"
    echo "  $0 create-key myuser custom-key-123"
    echo "  $0 list-keys myuser"
    echo "  $0 delete-key myuser key-id"
    ;;
esac
