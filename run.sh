#!/bin/bash
set -e

#
# Base parameters
#

DATASOURCE="mysql"
BASEURL="http://localhost:8080/guacamole"

echo "** Guacamole Login ($BASEURL) **"

#
# Read username
#

echo -n "Username: "
read USERNAME

#
# Read password
#

echo -n "Password: "
stty -echo
read PASSWORD
echo
stty echo

#
# Attempt authentication
#

TOKEN="$(curl --data-urlencode "username=$USERNAME" \
              --data-urlencode "password=$PASSWORD" \
              -s "$BASEURL/api/tokens" | jq -r '.authToken')"

# Verify whether login succeeded
if [ -z "$TOKEN" -o "$TOKEN" = "null" ]; then
    echo "Login failed."
    exit 1
fi

#
# Run all tests in "tests" directory
#

echo "** Beginning tests **"

# Include TOKEN and DATASOURCE in substitutable environment variables
export TOKEN
export DATASOURCE

for JSON in tests/*.json; do

    # Extract test name from filename
    NAME="$(basename "$JSON" ".json")"
    echo -n "$NAME ... "

    # Parse input parameters from JSON
    METHOD="$(envsubst < "$JSON" | jq -r ".request.method")"
    URL="$(envsubst < "$JSON" | jq -r ".request.url")"
    DATA="$(envsubst < "$JSON" | jq ".request.data")"

    # Parse expected response code from JSON
    EXPECTED_CODE="$(envsubst < "$JSON" | jq -r ".response.code")"

    # Parse declared response checks as key/value pairs, storing those pairs
    # as parallel pairs of lines (each key line is followed by its value line)
    CHECKS="$(envsubst < "$JSON" | jq -r '.response.checks // {} | to_entries[] | (.key + "\n" + (.value | tojson))')"

    # Make request
    if [ "$DATA" != "null" ]; then
        RESPONSE_CODE="$(curl -s -X "$METHOD"                       \
            -o "last-response.json" -w "%{http_code}"               \
            -H "Content-Type: application/json" --data-raw "$DATA"  \
            "$BASEURL/$URL")"
    else
        RESPONSE_CODE="$(curl -s -X "$METHOD"                       \
            -o "last-response.json" -w "%{http_code}"               \
            "$BASEURL/$URL")"
    fi

    # Verify response code
    if [ "$RESPONSE_CODE" != "$EXPECTED_CODE" ]; then
        echo "FAIL (expected HTTP $EXPECTED_CODE, got HTTP $RESPONSE_CODE)"
        exit 1
    fi

    # Verify each check passes
    echo "$CHECKS" | while read -r KEY; do
        read -r VALUE

        if ! jq -e "$KEY == $VALUE" "last-response.json" > /dev/null; then
            echo "FAIL ($KEY)"
            exit 1
        fi

    done

    # Test passes
    echo "OK"

done

echo "** Done **"

